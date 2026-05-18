from __future__ import annotations

import collections
import importlib
import logging
import math
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, cast

import numpy as np

from .segmentation import compute_statistics


def _bool_env(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


_USE_LINFORMER = _bool_env("REAL_USE_LINFORMER", True)
_USE_MAMBA = _bool_env("REAL_USE_MAMBA", True)
_MAMBA_STRICT = _bool_env("REAL_MAMBA_STRICT", False)


def _probe_import_in_subprocess(module_name: str, timeout_s: int = 20) -> tuple[bool, str]:
    code = f"import importlib; importlib.import_module('{module_name}')"
    try:
        proc = subprocess.run(
            [sys.executable, "-c", code],
            capture_output=True,
            text=True,
            timeout=timeout_s,
            check=False,
        )
    except Exception as exc:
        return False, f"probe failed for {module_name}: {exc}"

    if proc.returncode == 0:
        return True, ""

    err = (proc.stderr or proc.stdout or f"exit={proc.returncode}").strip()
    return False, f"subprocess import failed for {module_name}: {err[:300]}"

try:
    cv2 = cast(Any, importlib.import_module("cv2"))
except Exception as exc:
    cv2 = cast(Any, None)
    _CV2_IMPORT_ERROR = str(exc)
else:
    _CV2_IMPORT_ERROR = ""

try:
    torch = cast(Any, importlib.import_module("torch"))
    nn = cast(Any, importlib.import_module("torch.nn"))
    F = cast(Any, importlib.import_module("torch.nn.functional"))
except Exception as exc:
    torch = cast(Any, None)
    nn = cast(Any, None)
    F = cast(Any, None)
    _TORCH_IMPORT_ERROR = str(exc)
else:
    _TORCH_IMPORT_ERROR = ""

_LINFORMER_IMPORT_ERROR = ""
_MAMBA_IMPORT_ERROR = ""

if _USE_LINFORMER:
    _lin_ok, _lin_err = _probe_import_in_subprocess("linformer")
    try:
        Linformer = cast(Any, importlib.import_module("linformer").Linformer) if _lin_ok else None
    except Exception as exc:
        Linformer = None
        _LINFORMER_IMPORT_ERROR = str(exc)
    else:
        if not _lin_ok:
            _LINFORMER_IMPORT_ERROR = _lin_err
else:
    Linformer = None

if _USE_MAMBA:
    _mamba_ok, _mamba_err = _probe_import_in_subprocess("mamba_ssm")
    try:
        Mamba = cast(Any, importlib.import_module("mamba_ssm").Mamba) if _mamba_ok else None
    except Exception as exc:
        Mamba = None
        _MAMBA_IMPORT_ERROR = str(exc)
    else:
        if not _mamba_ok:
            _MAMBA_IMPORT_ERROR = _mamba_err
else:
    Mamba = None

_MAMBA_FALLBACK_ACTIVE = bool(_USE_MAMBA and Mamba is None and not _MAMBA_STRICT)

REAL_PIPELINE_NAME = "UNetLinformerMamba-real"
REAL_PIPELINE_VERSION = "1.0.0-notebook-port"

logger = logging.getLogger("ma_real")

_MODEL: Any = None
_DEVICE: Any = None
_CKPT_SHA256: str | None = None


# -------- Notebook-derived utils --------
def _strip_prefix(name: str):
    for prefix in ("module.", "model.", "net.", "ema."):
        if name.startswith(prefix):
            return name[len(prefix):]
    return name


_BLOCK_PATTERNS = (r"\.total_ops$", r"\.total_params$")


def _sanitize_state_dict(raw_sd, model):
    if not isinstance(raw_sd, (dict, collections.OrderedDict)):
        raise RuntimeError("Checkpoint tidak berisi dict state_dict.")

    block_res = [re.compile(p) for p in _BLOCK_PATTERNS]
    allowed = set(model.state_dict().keys())
    clean = collections.OrderedDict()

    for k, v in raw_sd.items():
        nk = _strip_prefix(k)
        if any(r.search(nk) for r in block_res):
            continue
        if nk in allowed and isinstance(v, torch.Tensor):
            clean[nk] = v

    if not clean:
        raise RuntimeError("State_dict hasil sanitasi kosong; cek ckpt & arsitektur.")

    return clean


def _sha256_of_file(path: Path) -> str:
    import hashlib

    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _deps_error() -> str:
    parts = []
    if torch is None:
        parts.append(f"torch unavailable: {_TORCH_IMPORT_ERROR}")
    if cv2 is None:
        parts.append(f"opencv unavailable: {_CV2_IMPORT_ERROR}")
    return "; ".join(parts)


def _feature_error() -> str:
    parts = []
    if _USE_LINFORMER and Linformer is None:
        parts.append(
            "linformer requested but unavailable"
            + (f": {_LINFORMER_IMPORT_ERROR}" if _LINFORMER_IMPORT_ERROR else "")
        )
    if _USE_MAMBA and Mamba is None:
        if _MAMBA_STRICT:
            parts.append(
                "mamba requested but unavailable"
                + (f": {_MAMBA_IMPORT_ERROR}" if _MAMBA_IMPORT_ERROR else "")
            )
    return "; ".join(parts)


if torch is not None and cv2 is not None:

    def _eca_kernel(c: int) -> int:
        k = int(round(math.log2(max(1, c))))
        k = k if k % 2 == 1 else k + 1
        return max(3, min(9, k))


    class ECA(nn.Module):
        def __init__(self, channels: int, k_size: int | None = None):
            super().__init__()
            k = _eca_kernel(channels) if k_size is None else int(k_size)
            self.conv = nn.Conv1d(1, 1, kernel_size=k, padding=(k - 1) // 2, bias=False)
            self.sigmoid = nn.Sigmoid()

        def forward(self, x):
            y = F.adaptive_avg_pool2d(x, 1).squeeze(-1).squeeze(-1)
            y = self.conv(y.unsqueeze(1)).squeeze(1)
            y = self.sigmoid(y).unsqueeze(-1).unsqueeze(-1)
            return x * y


    class DSConv(nn.Module):
        def __init__(self, in_ch, out_ch, stride=1, use_eca=False):
            super().__init__()
            self.dw = nn.Conv2d(in_ch, in_ch, 3, stride=stride, padding=1, groups=in_ch, bias=False)
            self.bn_dw = nn.BatchNorm2d(in_ch)
            self.act1 = nn.SiLU(inplace=True)
            self.pw = nn.Conv2d(in_ch, out_ch, 1, bias=False)
            self.bn_pw = nn.BatchNorm2d(out_ch)
            self.act2 = nn.SiLU(inplace=True)
            self.eca = ECA(out_ch) if use_eca else nn.Identity()

        def forward(self, x):
            x = self.act1(self.bn_dw(self.dw(x)))
            x = self.act2(self.bn_pw(self.pw(x)))
            return self.eca(x)


    class DoubleDSConv(nn.Module):
        def __init__(self, in_ch, out_ch, use_eca=True):
            super().__init__()
            self.ds1 = DSConv(in_ch, out_ch, 1, use_eca)
            self.ds2 = DSConv(out_ch, out_ch, 1, use_eca)
            self.proj = nn.Identity() if in_ch == out_ch else nn.Conv2d(in_ch, out_ch, 1, bias=False)
            self.bn = nn.BatchNorm2d(out_ch)

        def forward(self, x):
            skip = self.proj(x)
            x = self.ds2(self.ds1(x))
            return self.bn(x + skip)


    class EncoderBlock(nn.Module):
        def __init__(self, in_ch, out_ch, use_eca=True):
            super().__init__()
            self.feat = DoubleDSConv(in_ch, out_ch, use_eca=use_eca)
            self.down = DSConv(out_ch, out_ch, stride=2, use_eca=False)

        def forward(self, x):
            f = self.feat(x)
            p = self.down(f)
            return f, p


    class SEBLiteBlock(nn.Module):
        def __init__(self, channels: int, steps: int = 1, expand: int = 6, use_eca: bool = True):
            super().__init__()
            self.steps = steps
            self.pw1 = nn.Conv2d(channels, expand * channels, 1, bias=False)
            self.bn1 = nn.BatchNorm2d(expand * channels)
            self.dw = nn.Conv2d(
                expand * channels,
                expand * channels,
                3,
                padding=1,
                groups=expand * channels,
                bias=False,
            )
            self.bn2 = nn.BatchNorm2d(expand * channels)
            self.pw2 = nn.Conv2d(expand * channels, channels, 1, bias=False)
            self.bn3 = nn.BatchNorm2d(channels)
            self.fuse = DSConv(channels * 2, channels, 1, use_eca=use_eca)
            self.eca = ECA(channels) if use_eca else nn.Identity()
            self.act = nn.SiLU(inplace=True)

        def _ssb_once(self, x):
            s = F.avg_pool2d(x, 2)
            s = self.act(self.bn1(self.pw1(s)))
            s = self.act(self.bn2(self.dw(s)))
            s = self.bn3(self.pw2(s))
            s = F.interpolate(s, size=x.shape[-2:], mode="bilinear", align_corners=False)
            y = self.fuse(torch.cat([x, s], 1))
            return x + self.eca(y)

        def forward(self, x):
            for _ in range(self.steps):
                x = self._ssb_once(x)
            return x


    class EncoderBlockSEB(nn.Module):
        def __init__(self, in_ch, out_ch, steps=2, use_eca=True):
            super().__init__()
            self.stem = DSConv(in_ch, out_ch, 1, use_eca) if in_ch != out_ch else nn.Identity()
            self.seb = SEBLiteBlock(out_ch, steps=steps, expand=6, use_eca=use_eca)
            self.down = DSConv(out_ch, out_ch, 2, use_eca=False)

        def forward(self, x):
            x = self.stem(x) if not isinstance(self.stem, nn.Identity) else x
            f = self.seb(x)
            p = self.down(f)
            return f, p


    class SpatialAttentionGate(nn.Module):
        def __init__(self, F_g: int, F_l: int, F_int: int | None = None, use_eca: bool = True):
            super().__init__()
            F_int = int(F_int) if F_int is not None else max(8, min(F_g, F_l) // 2)
            self.g_ctx = nn.Sequential(
                nn.AdaptiveAvgPool2d(1),
                nn.Conv2d(F_g, F_int, kernel_size=1, bias=True),
                nn.BatchNorm2d(F_int),
            )
            self.x_proj = nn.Sequential(
                nn.Conv2d(F_l, F_int, kernel_size=1, bias=True),
                nn.BatchNorm2d(F_int),
            )
            self.psi = nn.Conv2d(F_int, 1, kernel_size=1, bias=True)
            self.act = nn.ReLU(inplace=True)
            self.sig = nn.Sigmoid()
            self.reduce = nn.Conv2d(F_l, F_g, kernel_size=1, bias=False)
            self.eca = ECA(F_l) if use_eca else nn.Identity()

        def forward(self, g, x):
            x = self.eca(x)
            B, _, H, W = x.shape
            s = self.g_ctx(g)
            s = s.expand(-1, -1, H, W)
            q = self.x_proj(x)
            a = self.act(q + s)
            a = self.sig(self.psi(a))
            x_att = x * a
            x_red = self.reduce(x_att)
            return x_red


    class DropPath(nn.Module):
        def __init__(self, p=0.0):
            super().__init__()
            self.p = float(p)

        def forward(self, x):
            if self.p == 0.0 or not self.training:
                return x
            keep = 1 - self.p
            shape = (x.shape[0],) + (1,) * (x.ndim - 1)
            return x * x.new_empty(shape).bernoulli_(keep).div_(keep)


    class LearnedPE(nn.Module):
        def __init__(self, dim, max_len):
            super().__init__()
            self.pe = nn.Parameter(torch.randn(1, max_len, dim) * 0.02)
            self.max_len = max_len

        def forward(self, x):
            B, N, D = x.shape
            if N > self.max_len:
                raise ValueError("seq len > max_len")
            return x + self.pe[:, :N, :]


    def _target_grid(H: int, W: int, max_tokens: int):
        if H * W <= max_tokens:
            return H, W

        scale = math.sqrt(float(max_tokens) / float(H * W))
        tH = max(1, int(math.floor(H * scale)))
        tW = max(1, int(math.floor(W * scale)))

        while tH * tW > max_tokens:
            if tH >= tW and tH > 1:
                tH -= 1
            elif tW > 1:
                tW -= 1
            else:
                break

        return tH, tW


    class ASPPLite(nn.Module):
        def __init__(self, in_ch, out_ch, dilations=(1, 3, 5), reduce=4, dropout=0.0):
            super().__init__()
            mid = max(8, in_ch // reduce)
            self.branches = nn.ModuleList(
                [
                    nn.Sequential(
                        nn.Conv2d(in_ch, in_ch, 3, padding=d, dilation=d, groups=in_ch, bias=False),
                        nn.BatchNorm2d(in_ch),
                        nn.SiLU(inplace=True),
                        nn.Conv2d(in_ch, mid, 1, bias=False),
                        nn.BatchNorm2d(mid),
                        nn.SiLU(inplace=True),
                    )
                    for d in dilations
                ]
            )
            self.imgp = nn.Sequential(
                nn.AdaptiveAvgPool2d(1),
                nn.Conv2d(in_ch, mid, 1, bias=False),
                nn.SiLU(inplace=True),
            )
            self.proj = nn.Sequential(
                nn.Conv2d(mid * (len(dilations) + 1), out_ch, 1, bias=False),
                nn.BatchNorm2d(out_ch),
                nn.SiLU(inplace=True),
                nn.Dropout2d(dropout) if dropout > 0 else nn.Identity(),
            )

        def forward(self, x):
            feats = [b(x) for b in self.branches]
            gp = self.imgp(x)
            gp = F.interpolate(gp, size=x.shape[-2:], mode="bilinear", align_corners=False)
            return self.proj(torch.cat(feats + [gp], 1))


    class LinformerBottleneck2D(nn.Module):
        def __init__(self, in_ch, dim=None, depth=1, heads=2, k=32, max_tokens=256, dropout=0.05):
            super().__init__()
            dim = in_ch if dim is None else int(dim)
            self.proj_in = nn.Conv2d(in_ch, dim, 1, bias=False)
            self.norm1 = nn.LayerNorm(dim)
            self.pos = LearnedPE(dim, max_tokens)
            if Linformer is None:
                raise ImportError("Linformer not available")
            self.lin = Linformer(dim=dim, seq_len=max_tokens, depth=depth, heads=heads, k=k, dropout=dropout)
            self.norm2 = nn.LayerNorm(dim)
            self.ffn = nn.Sequential(
                nn.Linear(dim, dim * 2),
                nn.GELU(),
                nn.Dropout(dropout),
                nn.Linear(dim * 2, dim),
                nn.Dropout(dropout),
            )
            self.proj_out = nn.Conv2d(dim, in_ch, 1, bias=False)
            self.aspp = ASPPLite(in_ch, in_ch, dropout=0.0)
            self.max_tokens = max_tokens
            self.dim = dim

        def forward(self, x):
            B, C, H, W = x.shape
            y = self.proj_in(x)
            tH, tW = _target_grid(H, W, self.max_tokens)
            y_small = F.adaptive_avg_pool2d(y, (tH, tW))
            N = tH * tW
            tok = y_small.flatten(2).transpose(1, 2).contiguous()
            tok = self.norm1(tok)
            tok = torch.nan_to_num(tok)
            if N < self.max_tokens:
                pad = tok.new_zeros(B, self.max_tokens - N, self.dim)
                attn = self.lin(self.pos(torch.cat([tok, pad], 1)))[:, :N, :]
            else:
                attn = self.lin(self.pos(tok))
            tok = tok + attn
            tok = self.norm2(tok)
            tok = torch.nan_to_num(tok)
            tok = tok + self.ffn(tok)
            feat = tok.transpose(1, 2).reshape(B, self.dim, tH, tW).contiguous()
            up = F.interpolate(feat, size=(H, W), mode="bilinear", align_corners=False)
            return torch.nan_to_num(self.proj_out(up) + self.aspp(x))


    class MobileBottleneck(nn.Module):
        def __init__(self, in_ch):
            super().__init__()
            self.aspp = ASPPLite(in_ch, in_ch, dropout=0.0)

        def forward(self, x):
            return self.aspp(x)


    class MambaDecoder(nn.Module):
        def __init__(self, up_in, skip_in, out_ch, dropout=0.05, droppath=0.05, use_mamba: bool = True):
            super().__init__()
            self.use_mamba = bool(use_mamba)
            self.up = nn.Sequential(
                nn.Upsample(scale_factor=2, mode="bilinear", align_corners=False),
                DSConv(up_in, out_ch, 1),
            )
            self.gate = SpatialAttentionGate(F_g=out_ch, F_l=skip_in, F_int=out_ch // 2, use_eca=True)
            self.merge = nn.Sequential(
                nn.Conv2d(out_ch * 2, out_ch, kernel_size=1, bias=False),
                nn.BatchNorm2d(out_ch),
                nn.ReLU(inplace=True),
            )
            self.drop2 = nn.Dropout2d(dropout) if dropout > 0 else nn.Identity()
            if self.use_mamba and Mamba is not None:
                self.ln = nn.LayerNorm(out_ch)
                self.mamba = Mamba(d_model=out_ch, d_state=16, d_conv=4, expand=2)
                self.dp = DropPath(droppath) if droppath > 0 else nn.Identity()
            else:
                self.ln = None
                self.mamba = None
                self.dp = nn.Identity()
            self.fuse = nn.Sequential(
                nn.Conv2d(out_ch, out_ch, kernel_size=3, padding=1, bias=False),
                nn.BatchNorm2d(out_ch),
                nn.ReLU(inplace=True),
            )

        def forward(self, x, skip):
            x = self.up(x)
            skip_gated = self.gate(x, skip)
            x = self.merge(torch.cat([x, skip_gated], dim=1))
            x = self.drop2(x)
            if self.use_mamba and self.mamba is not None and self.ln is not None:
                B, C, H, W = x.shape
                xf = x.flatten(2).transpose(1, 2).contiguous()
                y = self.mamba(self.ln(xf))
                x = (xf + self.dp(y)).transpose(1, 2).reshape(B, C, H, W).contiguous()
            return self.fuse(x)


    class UNetLinformerMamba(nn.Module):
        def __init__(
            self,
            in_channels: int = 1,
            base: int = 64,
            linformer_tokens: int = 256,
            *,
            use_linformer: bool = True,
            use_mamba: bool = True,
        ):
            super().__init__()
            self.in_channels = int(in_channels)
            self.use_linformer = bool(use_linformer)
            self.use_mamba = bool(use_mamba)
            ch1, ch2, ch3 = base, base * 2, base * 4
            self.enc1 = EncoderBlock(in_channels, ch1, use_eca=True)
            self.enc2 = EncoderBlock(ch1, ch2, use_eca=True)
            self.enc3 = EncoderBlockSEB(ch2, ch3, steps=1, use_eca=True)
            if self.use_linformer and Linformer is not None:
                self.bottleneck = LinformerBottleneck2D(
                    in_ch=ch3,
                    dim=ch3,
                    depth=1,
                    heads=2,
                    k=32,
                    max_tokens=linformer_tokens,
                    dropout=0.05,
                )
            else:
                self.bottleneck = MobileBottleneck(ch3)
            dprs = [0.03, 0.02, 0.01]
            self.dec3 = MambaDecoder(
                up_in=ch3,
                skip_in=ch3,
                out_ch=ch2,
                droppath=dprs[0],
                use_mamba=self.use_mamba,
            )
            self.dec2 = MambaDecoder(
                up_in=ch2,
                skip_in=ch2,
                out_ch=ch1,
                droppath=dprs[1],
                use_mamba=self.use_mamba,
            )
            self.dec1 = MambaDecoder(
                up_in=ch1,
                skip_in=ch1,
                out_ch=ch1,
                droppath=dprs[2],
                use_mamba=self.use_mamba,
            )
            self.pre_head_dropout = nn.Dropout2d(p=0.2)
            self.head = nn.Conv2d(ch1, 1, kernel_size=1, bias=True)
            self.head_act = nn.Sigmoid()
            for m in self.modules():
                if isinstance(m, nn.Conv2d):
                    nn.init.kaiming_normal_(m.weight, mode="fan_out", nonlinearity="relu")
                elif isinstance(m, nn.Linear):
                    nn.init.trunc_normal_(m.weight, std=0.02)
                if hasattr(m, "bias") and getattr(m, "bias", None) is not None:
                    nn.init.zeros_(m.bias)
            prior_p = 0.003
            with torch.no_grad():
                if self.head.bias is not None:
                    self.head.bias.fill_(math.log(prior_p / (1.0 - prior_p)))

        def forward(self, x, *, return_logits: bool = True):
            s1, p1 = self.enc1(x)
            s2, p2 = self.enc2(p1)
            s3, p3 = self.enc3(p2)
            b = self.bottleneck(p3)
            x3 = self.dec3(b, s3)
            x2 = self.dec2(x3, s2)
            x1 = self.dec1(x2, s1)
            x1 = self.pre_head_dropout(x1)
            logits = self.head(x1)
            return logits if return_logits else self.head_act(logits)


    def _preprocess_green_uint8(rgb_uint8, gamma=0.8, clahe_clip=2.0, clahe_tile=8):
        g_u8 = rgb_uint8[..., 1].astype(np.uint8)
        g_gamma = np.power((g_u8.astype(np.float32) + 1e-3) / 255.0, float(gamma))
        g_gamma_u8 = np.clip(gamma * 0 + g_gamma * 255.0, 0, 255).astype(np.uint8)
        clahe = cv2.createCLAHE(clipLimit=float(clahe_clip), tileGridSize=(int(clahe_tile), int(clahe_tile)))
        return clahe.apply(g_gamma_u8)


    def preprocess_image_for_sliding_window(image: np.ndarray) -> tuple[np.ndarray, tuple[int, int]]:
        original_size = image.shape[:2]
        target_W, target_H = 4288, 2848
        if image.shape[:2] != (target_H, target_W):
            image = cv2.resize(image, (target_W, target_H), interpolation=cv2.INTER_LINEAR)
        return image, original_size


    def _apply_min_area_numpy(mask_u8: np.ndarray, min_area: int) -> np.ndarray:
        if min_area is None or min_area <= 0:
            return mask_u8
        n, lab, stats, _ = cv2.connectedComponentsWithStats(mask_u8.astype(np.uint8), connectivity=8)
        if n <= 1:
            return mask_u8
        keep = np.zeros(n, dtype=np.uint8)
        keep[stats[:, cv2.CC_STAT_AREA] >= int(min_area)] = 1
        keep[0] = 0
        return keep[lab]


    def _hysteresis_bin_numpy(prob: np.ndarray, t_high: float, t_low: float) -> np.ndarray:
        strong = (prob >= float(t_high)).astype(np.uint8)
        weak = (prob >= float(t_low)).astype(np.uint8)
        n, lab = cv2.connectedComponents(weak, connectivity=8)
        if n <= 1:
            return strong
        keep = np.zeros(n, np.uint8)
        hit = np.unique(lab[strong > 0])
        keep[hit] = 1
        keep[0] = 0
        return keep[lab]


    def postprocess_mask(
        prob,
        original_size,
        *,
        threshold: float = 0.75,
        min_area: int = 3,
        use_hysteresis: bool = True,
        hysteresis_low_offset: float = 0.30,
    ):
        if isinstance(prob, torch.Tensor):
            prob = prob.detach().cpu().numpy()

        Horig, Worig = original_size
        if prob.shape[:2] != (Horig, Worig):
            prob = cv2.resize(prob, (Worig, Horig), interpolation=cv2.INTER_LINEAR)

        if use_hysteresis:
            t_high = float(threshold)
            t_low = max(0.0, t_high - float(hysteresis_low_offset))
            mask = _hysteresis_bin_numpy(prob, t_high, t_low)
        else:
            mask = (prob >= float(threshold)).astype(np.uint8)

        if min_area > 0:
            mask = _apply_min_area_numpy(mask, int(min_area))

        mask = (mask * 255).astype(np.uint8)
        return mask


    def load_model(checkpoint_path: str, device: str = "auto", unsafe_ok: bool = False):
        if device == "auto":
            dev = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        else:
            dev = torch.device(device)

        model = UNetLinformerMamba(
            in_channels=1,
            base=64,
            linformer_tokens=256,
            use_linformer=(_USE_LINFORMER and Linformer is not None),
            use_mamba=(_USE_MAMBA and Mamba is not None),
        )

        ckpt_path = Path(checkpoint_path)
        if not ckpt_path.exists():
            raise FileNotFoundError(f"Checkpoint not found: {ckpt_path}")

        try:
            add_safe_globals = importlib.import_module("torch.serialization").add_safe_globals
            from codecs import encode as codecs_encode
            from numpy.core.multiarray import _reconstruct as np_reconstruct

            add_safe_globals([np_reconstruct, np.ndarray, np.dtype, codecs_encode])
        except Exception as exc:
            logger.warning("add_safe_globals failed: %s", exc)

        try:
            checkpoint = torch.load(ckpt_path, map_location=dev, weights_only=True)
        except Exception as exc:
            if not unsafe_ok:
                raise RuntimeError(
                    "weights_only load gagal. Set REAL_UNSAFE_LOAD=true bila checkpoint tepercaya."
                ) from exc
            checkpoint = torch.load(ckpt_path, map_location=dev, weights_only=False)

        if isinstance(checkpoint, dict) and "model_state" in checkpoint:
            state_dict = checkpoint["model_state"]
        elif isinstance(checkpoint, dict) and "state_dict" in checkpoint:
            state_dict = checkpoint["state_dict"]
        else:
            state_dict = checkpoint

        state_dict = _sanitize_state_dict(state_dict, model)
        model.load_state_dict(state_dict, strict=True)
        model = model.to(dev).eval()

        return model, dev


    def sliding_window_inference(
        model,
        image: np.ndarray,
        device,
        window_size: int = 256,
        stride: int = 128,
        temperature: float = 1.0,
    ) -> np.ndarray:
        model.eval()

        g_u8 = _preprocess_green_uint8(image, gamma=0.8, clahe_clip=2.0, clahe_tile=8)
        processed = g_u8.astype(np.float32) / 255.0

        H, W = processed.shape
        prob_map = np.zeros((H, W), dtype=np.float32)
        count_map = np.zeros((H, W), dtype=np.float32)

        def _positions(full, win, st, offset=0):
            start = int(offset) % max(1, st)
            pos = list(range(start, max(full - win, 0) + 1, st))
            if not pos or pos[-1] != full - win:
                pos.append(max(full - win, 0))
            return pos

        ys = _positions(H, window_size, stride, offset=0)
        xs = _positions(W, window_size, stride, offset=0)

        with torch.no_grad():
            for y in ys:
                for x in xs:
                    window = processed[y : y + window_size, x : x + window_size]
                    window_tensor = torch.from_numpy(window).unsqueeze(0).unsqueeze(0).to(device)

                    with torch.amp.autocast("cuda", enabled=(device.type == "cuda")):
                        logits = model(window_tensor, return_logits=True)

                    prob = torch.sigmoid(logits.squeeze() / temperature).cpu().numpy()
                    h_actual, w_actual = prob.shape
                    prob_map[y : y + h_actual, x : x + w_actual] += prob
                    count_map[y : y + h_actual, x : x + w_actual] += 1.0

            if device.type == "cuda":
                torch.cuda.synchronize()

        prob_map = prob_map / np.maximum(count_map, 1.0)
        return prob_map


# -------- readiness flags --------
if torch is None or cv2 is None:
    REAL_PIPELINE_READY = False
    REAL_PIPELINE_ERROR = _deps_error() or "Real dependencies unavailable"
else:
    if _MAMBA_FALLBACK_ACTIVE:
        logger.warning(
            "REAL_USE_MAMBA=true but mamba_ssm is unavailable; "
            "falling back to non-mamba decoder (set REAL_MAMBA_STRICT=true to require mamba)."
        )
    _feature_err = _feature_error()
    if _feature_err:
        REAL_PIPELINE_READY = False
        REAL_PIPELINE_ERROR = _feature_err
    else:
        _ckpt = os.getenv("CKPT_PATH", "").strip()
        if not _ckpt:
            REAL_PIPELINE_READY = False
            REAL_PIPELINE_ERROR = "CKPT_PATH is empty"
        elif not Path(_ckpt).exists():
            REAL_PIPELINE_READY = False
            REAL_PIPELINE_ERROR = f"Checkpoint not found: {_ckpt}"
        else:
            REAL_PIPELINE_READY = True
            REAL_PIPELINE_ERROR = ""


def _ensure_model_loaded() -> tuple[Any, Any]:
    global _MODEL, _DEVICE, _CKPT_SHA256

    if torch is None or cv2 is None:
        raise RuntimeError(REAL_PIPELINE_ERROR or _deps_error() or "Dependency error")

    ckpt_path = os.getenv("CKPT_PATH", "").strip()
    if not ckpt_path:
        raise RuntimeError("CKPT_PATH is empty")

    ckpt_file = Path(ckpt_path)
    if not ckpt_file.exists():
        raise RuntimeError(f"Checkpoint not found: {ckpt_file}")

    sha = _sha256_of_file(ckpt_file)
    if _MODEL is not None and _DEVICE is not None and _CKPT_SHA256 == sha:
        return _MODEL, _DEVICE

    device = os.getenv("REAL_DEVICE", "auto")
    unsafe_ok = _bool_env("REAL_UNSAFE_LOAD", False)

    model, dev = load_model(checkpoint_path=ckpt_path, device=device, unsafe_ok=unsafe_ok)
    _MODEL = model
    _DEVICE = dev
    _CKPT_SHA256 = sha

    logger.info("Real model loaded: ckpt=%s device=%s", ckpt_file, dev)
    return _MODEL, _DEVICE


def predict(rgb_u8: np.ndarray, threshold: float) -> tuple[np.ndarray, np.ndarray, dict[str, Any], dict[str, float]]:
    if not REAL_PIPELINE_READY:
        raise RuntimeError(REAL_PIPELINE_ERROR or "Real pipeline is not ready")

    model, device = _ensure_model_loaded()

    t0 = time.perf_counter()
    img_resized, original_size = preprocess_image_for_sliding_window(rgb_u8)
    t1 = time.perf_counter()

    prob_map = sliding_window_inference(
        model,
        img_resized,
        device,
        window_size=256,
        stride=128,
        temperature=1.0,
    )
    t2 = time.perf_counter()

    mask_u8 = postprocess_mask(
        prob_map,
        original_size,
        threshold=float(threshold),
        min_area=int(os.getenv("REAL_MIN_AREA", "3")),
        use_hysteresis=True,
        hysteresis_low_offset=0.30,
    )
    stats = compute_statistics(mask_u8)
    t3 = time.perf_counter()

    timing = {
        "pre_ms": round((t1 - t0) * 1000.0, 3),
        "infer_ms": round((t2 - t1) * 1000.0, 3),
        "post_ms": round((t3 - t2) * 1000.0, 3),
    }

    return prob_map.astype(np.float32), mask_u8, stats, timing
