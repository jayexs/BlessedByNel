param([string]$In, [string]$Out)
# Crops each portfolio photo to 4:5, levels and color-balances it, sharpens lightly, and saves a web JPEG.
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class Enhance {
  public static void Run(string src, string dst, int cx, int cy, int cwIn, int w, int h) {
    using (var orig = new Bitmap(src)) {
      int cw = cwIn > 0 ? cwIn : orig.Width, ch = (int)Math.Round(cw * (double)h / w);
      if (cy + ch > orig.Height) cy = orig.Height - ch;
      var bmp = new Bitmap(w, h, PixelFormat.Format24bppRgb);
      using (var g = Graphics.FromImage(bmp)) {
        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
        g.SmoothingMode = SmoothingMode.HighQuality;
        g.DrawImage(orig, new Rectangle(0, 0, w, h), new Rectangle(cx, cy, cw, ch), GraphicsUnit.Pixel);
      }
      var r = new Rectangle(0, 0, w, h);
      var d = bmp.LockBits(r, ImageLockMode.ReadWrite, PixelFormat.Format24bppRgb);
      int stride = d.Stride; var px = new byte[stride * h];
      Marshal.Copy(d.Scan0, px, 0, px.Length);

      // Per-channel levels from 0.4% / 99.6% percentiles, blended halfway so color casts soften without going flat.
      double[] lo = new double[3], hi = new double[3];
      for (int c = 0; c < 3; c++) {
        var hist = new int[256]; long n = 0;
        for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) { hist[px[y * stride + x * 3 + c]]++; n++; }
        long acc = 0; int a = 0, b = 255;
        for (int i = 0; i < 256; i++) { acc += hist[i]; if (acc > n * 0.004) { a = i; break; } }
        acc = 0;
        for (int i = 255; i >= 0; i--) { acc += hist[i]; if (acc > n * 0.004) { b = i; break; } }
        lo[c] = a * 0.5; hi[c] = 255 - (255 - b) * 0.5;
      }
      var outp = new double[stride * h];
      for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
        int i = y * stride + x * 3;
        double B = (px[i] - lo[0]) / (hi[0] - lo[0]), G = (px[i + 1] - lo[1]) / (hi[1] - lo[1]), R = (px[i + 2] - lo[2]) / (hi[2] - lo[2]);
        // gentle S-curve for contrast, then a touch of saturation
        Func<double, double> s = v => { v = Math.Max(0, Math.Min(1, v)); return v * 0.78 + 0.22 * v * v * (3 - 2 * v); };
        B = s(B); G = s(G); R = s(R);
        double L = 0.299 * R + 0.587 * G + 0.114 * B, sat = 1.06;
        outp[i] = L + (B - L) * sat; outp[i + 1] = L + (G - L) * sat; outp[i + 2] = L + (R - L) * sat;
      }
      // Unsharp mask: 5x5 box blur difference, amount 0.45.
      var res = new byte[px.Length];
      for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) for (int c = 0; c < 3; c++) {
        double sum = 0; int cnt = 0;
        for (int dy = -2; dy <= 2; dy++) { int yy = y + dy; if (yy < 0 || yy >= h) continue;
          for (int dx = -2; dx <= 2; dx++) { int xx = x + dx; if (xx < 0 || xx >= w) continue; sum += outp[yy * stride + xx * 3 + c]; cnt++; } }
        double v = outp[y * stride + x * 3 + c]; v = v + 0.45 * (v - sum / cnt);
        res[y * stride + x * 3 + c] = (byte)Math.Max(0, Math.Min(255, Math.Round(v * 255)));
      }
      Marshal.Copy(res, 0, d.Scan0, res.Length);
      bmp.UnlockBits(d);
      var enc = Array.Find(ImageCodecInfo.GetImageEncoders(), e => e.MimeType == "image/jpeg");
      var ps = new EncoderParameters(1); ps.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, 80L);
      bmp.Save(dst, enc, ps);
      bmp.Dispose();
    }
  }
}
"@
New-Item -ItemType Directory -Force $Out | Out-Null
# file, crop top, crop left, crop width (original pixels; width 0 = full width), output name, output size
$jobs = @(@("1.jpg", 560, 0, 0, "1", 880, 1100), @("2.jpg", 520, 0, 0, "2", 880, 1100), @("3.jpg", 500, 0, 0, "3", 880, 1100),
  @("4.jpg", 520, 0, 0, "4", 880, 1100), @("5.jpg", 380, 0, 0, "5", 880, 1100), @("6.png", 700, 0, 1100, "6", 880, 1100),
  @("6.png", 855, 0, 990, "face", 720, 720))
foreach ($j in $jobs) {
  $name = $j[4]
  [Enhance]::Run((Join-Path $In $j[0]), (Join-Path $Out "$name.jpg"), $j[2], $j[1], $j[3], $j[5], $j[6])
  "{0}.jpg  {1:N0} KB" -f $name, ((Get-Item (Join-Path $Out "$name.jpg")).Length / 1KB)
}
