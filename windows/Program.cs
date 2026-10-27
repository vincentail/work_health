// WorkHealth for Windows：系统托盘小工具，久坐提醒起身活动、定时提醒喝水
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace WorkHealth
{
    // MARK: - 偏好设置（%APPDATA%\WorkHealth\settings.ini）

    static class Prefs
    {
        static readonly string Dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "WorkHealth");
        static readonly string FilePath = Path.Combine(Dir, "settings.ini");
        static readonly Dictionary<string, string> d = Load();

        static Dictionary<string, string> Load()
        {
            var r = new Dictionary<string, string>();
            try
            {
                foreach (var line in File.ReadAllLines(FilePath))
                {
                    var i = line.IndexOf('=');
                    if (i > 0) r[line.Substring(0, i)] = line.Substring(i + 1);
                }
            }
            catch { }
            return r;
        }

        static void Set(string key, object value)
        {
            d[key] = value.ToString();
            try
            {
                Directory.CreateDirectory(Dir);
                File.WriteAllLines(FilePath, d.Select(kv => kv.Key + "=" + kv.Value));
            }
            catch { }
        }

        static int Int(string key, int def) =>
            d.TryGetValue(key, out var v) && int.TryParse(v, out var n) ? n : def;

        /// 连续久坐多少分钟后提醒
        public static int SitMinutes { get => Int("sitMinutes", 45); set => Set("sitMinutes", value); }
        /// 每次活动多少分钟
        public static int BreakMinutes { get => Int("breakMinutes", 5); set => Set("breakMinutes", value); }
        /// 喝水提醒间隔（分钟），0 表示关闭
        public static int WaterMinutes { get => Int("waterMinutes", 30); set => Set("waterMinutes", value); }
        /// 离开电脑（无键鼠操作）多少分钟视为已经休息过
        public static int IdleResetMinutes { get => Int("idleResetMinutes", 5); set => Set("idleResetMinutes", value); }
        /// 稍后提醒的分钟数
        public static int SnoozeMinutes { get => Int("snoozeMinutes", 10); set => Set("snoozeMinutes", value); }
        public static int WaterGoal { get => Int("waterGoal", 8); set => Set("waterGoal", value); }
        /// 每天几点开始提醒（从 0 点起的分钟数），-1 表示不限
        public static int StartMinute { get => Int("startMinute", -1); set => Set("startMinute", value); }
        /// 每天几点结束提醒（从 0 点起的分钟数），-1 表示不限
        public static int EndMinute { get => Int("endMinute", -1); set => Set("endMinute", value); }
        public static bool SoundOn { get => Int("soundOn", 1) != 0; set => Set("soundOn", value ? 1 : 0); }
        /// 提示音：C:\Windows\Media 下的声音名，或自定义音频文件的绝对路径
        public static string SoundName
        {
            get => d.TryGetValue("soundName", out var v) ? v : "Windows Notify System Generic";
            set => Set("soundName", value);
        }

        /// 提醒弹窗里的宠物：cat / dog / none
        public static string Pet { get => d.TryGetValue("pet", out var v) ? v : "cat"; set => Set("pet", value); }

        public static string Clock(int minute) => $"{minute / 60}:{minute % 60:00}";

        static string TodayKey => "water-" + DateTime.Now.ToString("yyyy-MM-dd");
        public static int WaterToday { get => Int(TodayKey, 0); set => Set(TodayKey, value); }
    }

    // MARK: - 提示音

    static class Sounds
    {
        static string MediaDir => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "Media");

        /// C:\Windows\Media 下的 wav 声音名
        public static string[] Available
        {
            get
            {
                try { return Directory.GetFiles(MediaDir, "*.wav").Select(Path.GetFileNameWithoutExtension).OrderBy(x => x).ToArray(); }
                catch { return new string[0]; }
            }
        }

        public static bool IsCustom(string name) => Path.IsPathRooted(name);
        public static string Label(string name) => IsCustom(name) ? Path.GetFileName(name) : name;

        [DllImport("winmm.dll", CharSet = CharSet.Unicode)]
        static extern int mciSendString(string command, StringBuilder ret, int retLength, IntPtr callback);

        /// 用 MCI 播放，wav / mp3 / wma 都支持
        public static void Play(string name = null)
        {
            name = name ?? Prefs.SoundName;
            var path = IsCustom(name) ? name : Path.Combine(MediaDir, name + ".wav");
            mciSendString("close whsound", null, 0, IntPtr.Zero);
            if (!File.Exists(path)
                || mciSendString($"open \"{path}\" type mpegvideo alias whsound", null, 0, IntPtr.Zero) != 0
                || mciSendString("play whsound", null, 0, IntPtr.Zero) != 0)
                System.Media.SystemSounds.Asterisk.Play();
        }
    }

    // MARK: - 开机启动（注册表 Run 项）

    static class LoginItem
    {
        const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        const string Name = "WorkHealth";

        public static bool IsEnabled
        {
            get { using (var k = Registry.CurrentUser.OpenSubKey(RunKey)) return k?.GetValue(Name) != null; }
        }

        public static void SetEnabled(bool on)
        {
            using (var k = Registry.CurrentUser.CreateSubKey(RunKey))
            {
                if (on) k.SetValue(Name, $"\"{Application.ExecutablePath}\"");
                else k.DeleteValue(Name, false);
            }
        }
    }

    // MARK: - 系统接口

    static class Native
    {
        [StructLayout(LayoutKind.Sequential)]
        struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }

        [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO info);
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
        [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr handle);
        [DllImport("user32.dll")] public static extern bool ReleaseCapture();
        [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
        [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

        /// 距离上次键盘/鼠标操作的秒数
        public static double IdleSeconds
        {
            get
            {
                var info = new LASTINPUTINFO { cbSize = (uint)Marshal.SizeOf<LASTINPUTINFO>() };
                return GetLastInputInfo(ref info) ? unchecked((uint)Environment.TickCount - info.dwTime) / 1000.0 : 0;
            }
        }
    }

    // MARK: - 宠物动画

    /// Calm：呼吸、招手；Active：蹦跳（活动中）；Happy：眯眼开心（活动完成）
    enum PetMood { Calm, Active, Happy }

    /// 弹窗里的小猫/小狗，纯代码绘制，带呼吸、眨眼、摇尾巴、招手动画；旁边的气泡里显示提醒 emoji
    sealed class PetControl : Control
    {
        readonly bool cat;
        readonly PetMood mood;
        readonly string emoji;
        readonly float scale;
        readonly DateTime start = DateTime.Now;
        readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer { Interval = 33 };

        public PetControl(string pet, PetMood mood, string emoji, float scale)
        {
            cat = pet == "cat";
            this.mood = mood;
            this.emoji = emoji;
            this.scale = scale;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);
            Size = new Size((int)(170 * scale), (int)(112 * scale));
            timer.Tick += (s, e) => Invalidate();
            timer.Start();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) timer.Dispose();
            base.Dispose(disposing);
        }

        static Color C(int rgb, int alpha = 255) => Color.FromArgb(alpha, (rgb >> 16) & 0xff, (rgb >> 8) & 0xff, rgb & 0xff);
        static PointF P(float x, float y) => new PointF(x, y);

        static void Oval(Graphics g, float cx, float cy, float w, float h, Color c)
        {
            using (var b = new SolidBrush(c)) g.FillEllipse(b, cx - w / 2, cy - h / 2, w, h);
        }

        static void Poly(Graphics g, Color c, params PointF[] points)
        {
            using (var b = new SolidBrush(c)) g.FillPolygon(b, points);
        }

        static void Stroke(Graphics g, float width, Color c, Action<GraphicsPath> build)
        {
            using (var path = new GraphicsPath())
            using (var pen = new Pen(c, width) { StartCap = LineCap.Round, EndCap = LineCap.Round })
            {
                build(path);
                g.DrawPath(pen, path);
            }
        }

        /// 二次贝塞尔曲线（转成三次）
        static void Quad(GraphicsPath p, PointF a, PointF c, PointF b) =>
            p.AddBezier(a, P(a.X + 2f / 3 * (c.X - a.X), a.Y + 2f / 3 * (c.Y - a.Y)),
                        P(b.X + 2f / 3 * (c.X - b.X), b.Y + 2f / 3 * (c.Y - b.Y)), b);

        static void Rotated(Graphics g, double angle, PointF p, Action body)
        {
            var state = g.Save();
            g.TranslateTransform(p.X, p.Y);
            g.RotateTransform((float)(angle * 180 / Math.PI));
            g.TranslateTransform(-p.X, -p.Y);
            body();
            g.Restore(state);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.Clear(BackColor);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.ScaleTransform(scale, scale);
            var t = (DateTime.Now - start).TotalSeconds;
            Color fur = C(cat ? 0xF6A04D : 0xE3B577), cream = C(0xFFF3E0), ink = C(0x3B2A20), pink = C(0xF28CA0);

            float hop = mood == PetMood.Calm ? 1.5f + 1.5f * (float)Math.Sin(t * 2.4)
                      : mood == PetMood.Active ? 9 * (float)Math.Abs(Math.Sin(t * 5))
                      : 5 * (float)Math.Abs(Math.Sin(t * 4));
            Oval(g, 85, 106, 62 - hop * 2, 8, C(0x000000, 31));

            var outer = g.Save();
            g.TranslateTransform(25, -hop);

            // 尾巴
            var wag = Math.Sin(t * (cat ? 3 : mood == PetMood.Calm ? 8 : 14)) * (cat ? 0.35 : 0.5);
            Rotated(g, wag, P(80, 88), () => Stroke(g, cat ? 9 : 8, fur, p =>
            {
                if (cat) Quad(p, P(80, 88), P(112, 90), P(104, 50));
                else Quad(p, P(80, 88), P(100, 88), P(102, 68));
            }));

            // 身体和脚
            Oval(g, 60, 82, 58, 40, fur);
            Oval(g, 60, 86, 30, 24, cream);
            var waving = mood == PetMood.Calm && t % 4 < 1.6;
            Oval(g, 46, 100, 16, 10, fur);
            if (!waving) Oval(g, 74, 100, 16, 10, fur);

            // 猫耳朵（右耳偶尔抖一下）
            if (cat)
            {
                Poly(g, fur, P(32, 36), P(36, 6), P(56, 24));
                Poly(g, pink, P(38, 30), P(39, 13), P(51, 24));
                Rotated(g, t % 5 < 0.2 ? 0.18 : 0, P(76, 30), () =>
                {
                    Poly(g, fur, P(88, 36), P(84, 6), P(64, 24));
                    Poly(g, pink, P(82, 30), P(81, 13), P(69, 24));
                });
            }

            // 头
            Oval(g, 60, 48, 66, 56, fur);
            if (cat)
            {
                Stroke(g, 3, C(0xD97F2E), p =>
                {
                    foreach (var x in new float[] { 54, 60, 66 })
                    {
                        p.StartFigure();
                        p.AddLine(x, x == 60 ? 22 : 24, x, 31);
                    }
                });
            }
            else
            {
                // 狗：耷拉的耳朵会轻轻晃，嘴巴一圈浅色
                var flap = Math.Sin(t * 3) * 0.08;
                Rotated(g, 0.35 + flap, P(30, 30), () => Oval(g, 30, 46, 20, 38, C(0x9C6B3E)));
                Rotated(g, -0.35 - flap, P(90, 30), () => Oval(g, 90, 46, 20, 38, C(0x9C6B3E)));
                Oval(g, 60, 60, 30, 20, cream);
            }

            // 眼睛：开心时眯成 ^ ^，平时每隔几秒眨一次
            foreach (var x in new float[] { 47, 73 })
            {
                const float y = 48;
                if (mood == PetMood.Happy)
                    Stroke(g, 2.5f, ink, p => Quad(p, P(x - 5, y + 2), P(x, y - 6), P(x + 5, y + 2)));
                else if (t % 3.4 > 3.25)
                    Stroke(g, 2.5f, ink, p => p.AddLine(x - 4, y, x + 4, y));
                else
                {
                    Oval(g, x, y, 8, 10, ink);
                    Oval(g, x + 1.5f, y - 2.5f, 3, 3, Color.White);
                }
            }

            // 腮红、鼻子、嘴
            Oval(g, 38, 60, 10, 6, C(0xF28CA0, 115));
            Oval(g, 82, 60, 10, 6, C(0xF28CA0, 115));
            if (cat) Poly(g, pink, P(56, 55), P(64, 55), P(60, 59.5f));
            else Oval(g, 60, 56, 12, 8, ink);
            if (!cat && mood != PetMood.Calm) Oval(g, 60, 67, 9, 11, C(0xF06A80));
            Stroke(g, 1.6f, ink, p =>
            {
                p.AddLine(60, 59, 60, 62);
                p.StartFigure();
                Quad(p, P(54, 61), P(57, 66), P(60, 62));
                Quad(p, P(60, 62), P(63, 66), P(66, 61));
            });
            if (cat)
            {
                Stroke(g, 1.2f, C(0x3B2A20, 128), p =>
                {
                    p.StartFigure(); p.AddLine(36, 58, 22, 55);
                    p.StartFigure(); p.AddLine(36, 62, 22, 64);
                    p.StartFigure(); p.AddLine(84, 58, 98, 55);
                    p.StartFigure(); p.AddLine(84, 62, 98, 64);
                });
            }

            // 招手
            if (waving)
            {
                var y = 64 + (float)Math.Sin(t * 12) * 4;
                Oval(g, 95, y, 15, 15, fur);
                Oval(g, 95, y + 2, 7, 5, C(0xF28CA0, 204));
            }
            g.Restore(outer);

            // 气泡
            var by = 4 + (float)Math.Sin(t * 2) * 2;
            var bubble = new RectangleF(120, by, 46, 40);
            using (var path = new GraphicsPath())
            using (var border = new Pen(C(0xCBD5E1)))
            {
                const float r = 14;
                path.AddArc(bubble.Left, bubble.Top, r * 2, r * 2, 180, 90);
                path.AddArc(bubble.Right - r * 2, bubble.Top, r * 2, r * 2, 270, 90);
                path.AddArc(bubble.Right - r * 2, bubble.Bottom - r * 2, r * 2, r * 2, 0, 90);
                path.AddArc(bubble.Left, bubble.Bottom - r * 2, r * 2, r * 2, 90, 90);
                path.CloseFigure();
                path.AddEllipse(124, by + 43, 7, 7);
                g.FillPath(Brushes.White, path);
                g.DrawPath(border, path);
            }
            using (var font = new Font("Segoe UI Emoji", 20, GraphicsUnit.Pixel))
            using (var format = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
                g.DrawString(emoji, font, Brushes.Black, bubble, format);
        }
    }

    // MARK: - 提醒弹窗（置顶、居中）

    sealed class PromptWindow : Form
    {
        public readonly Label MessageLabel;
        readonly float scale;

        int Px(float v) => (int)Math.Round(v * scale);

        public PromptWindow(string emoji, string title, string message, PetMood mood, params Button[] buttons)
        {
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.CenterScreen;
            TopMost = true;
            ShowInTaskbar = false;
            BackColor = Color.FromArgb(248, 250, 252);
            using (var g = CreateGraphics()) scale = g.DpiX / 96f;

            int width = Px(440), y = Px(28);
            Label Add(string text, Font font, Color color)
            {
                var size = TextRenderer.MeasureText(text, font, new Size(width - Px(60), 0), TextFormatFlags.WordBreak);
                var l = new Label
                {
                    Text = text, Font = font, ForeColor = color, TextAlign = ContentAlignment.TopCenter,
                    Bounds = new Rectangle(Px(30), y, width - Px(60), size.Height),
                };
                l.MouseDown += DragWindow;
                Controls.Add(l);
                y += size.Height + Px(8);
                return l;
            }
            if (Prefs.Pet == "none")
                Add(emoji, new Font("Segoe UI Emoji", 34f), Color.FromArgb(15, 23, 42));
            else
            {
                var pet = new PetControl(Prefs.Pet, mood, emoji, scale) { BackColor = BackColor };
                pet.Location = new Point((width - pet.Width) / 2, y);
                pet.MouseDown += DragWindow;
                Controls.Add(pet);
                y += pet.Height + Px(6);
            }
            Add(title, new Font("Microsoft YaHei UI", 15f, FontStyle.Bold), Color.FromArgb(15, 23, 42));
            // 留出两行高度，活动倒计时更新文字时不用重新排版
            MessageLabel = Add(message.Contains("\n") ? message : message + "\n", new Font("Microsoft YaHei UI", 10.5f),
                               Color.FromArgb(100, 116, 139));
            MessageLabel.Text = message;
            y += Px(12);

            int x = (width - buttons.Sum(b => b.Width) - Px(10) * (buttons.Length - 1)) / 2;
            foreach (var b in buttons)
            {
                b.Location = new Point(x, y);
                Controls.Add(b);
                x += b.Width + Px(10);
            }
            if (buttons.Length > 0) AcceptButton = buttons[0];
            ClientSize = new Size(width, y + buttons.Max(b => b.Height) + Px(26));
            MouseDown += DragWindow;
        }

        /// 统一样式的按钮，第一个按钮用主色
        public static Button MakeButton(string text, bool primary, Action handler)
        {
            var font = new Font("Microsoft YaHei UI", 10f);
            float s;
            using (var g = Graphics.FromHwnd(IntPtr.Zero)) s = g.DpiX / 96f;
            var b = new Button
            {
                Text = text, Font = font, FlatStyle = FlatStyle.Flat, Cursor = Cursors.Hand,
                Size = new Size(TextRenderer.MeasureText(text, font).Width + (int)(40 * s), (int)(36 * s)),
                BackColor = primary ? Color.FromArgb(37, 99, 235) : Color.FromArgb(226, 232, 240),
                ForeColor = primary ? Color.White : Color.FromArgb(15, 23, 42),
            };
            b.FlatAppearance.BorderSize = 0;
            b.Click += (_, __) => handler();
            return b;
        }

        void DragWindow(object sender, MouseEventArgs e)
        {
            if (e.Button != MouseButtons.Left) return;
            Native.ReleaseCapture();
            Native.SendMessage(Handle, 0xA1 /* WM_NCLBUTTONDOWN */, (IntPtr)2 /* HTCAPTION */, IntPtr.Zero);
        }

        protected override CreateParams CreateParams
        {
            get
            {
                var cp = base.CreateParams;
                cp.ClassStyle |= 0x20000; // CS_DROPSHADOW
                return cp;
            }
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            int round = 2; // Windows 11 圆角，Windows 10 上忽略
            Native.DwmSetWindowAttribute(Handle, 33, ref round, sizeof(int));
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            using (var pen = new Pen(Color.FromArgb(203, 213, 225)))
                e.Graphics.DrawRectangle(pen, 0, 0, ClientSize.Width - 1, ClientSize.Height - 1);
        }
    }

    // MARK: - 主逻辑

    sealed class App : ApplicationContext
    {
        readonly NotifyIcon tray = new NotifyIcon();
        readonly ContextMenuStrip menu = new ContextMenuStrip();
        readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer { Interval = 1000 };
        readonly Control ui = new Control();
        IntPtr iconHandle;
        string iconKey;

        DateTime sitStart = DateTime.Now;     // 本轮久坐开始时间
        DateTime lastWater = DateTime.Now;    // 上次喝水时间
        DateTime? sitSnoozeUntil;
        DateTime? waterSnoozeUntil;
        DateTime? pausedUntil;                // 暂停提醒（MaxValue = 手动恢复）
        DateTime? breakEnd;                   // 正在活动时的结束时间

        enum PromptKind { Sit, Water, OnBreak, Done }
        PromptWindow prompt;
        PromptKind? promptKind;

        static readonly Random random = new Random();
        static readonly string[] sitTips =
        {
            "站起来伸个懒腰，转转脖子和肩膀",
            "去接杯水，顺便走两步",
            "做 10 个深蹲，或者靠墙站一会儿",
            "望望窗外远处，让眼睛也休息一下",
            "活动一下手腕和腰，别让颈椎太累",
        };
        static readonly string[] waterTips =
        {
            "小口慢喝一杯温水（约 200ml）",
            "口渴时其实已经缺水了，现在就喝一点",
            "喝口水，顺便让眼睛离开屏幕 20 秒",
        };

        public App()
        {
            var _ = ui.Handle; // 创建句柄，供系统事件切回界面线程

            menu.Opening += (s, e) => { BuildMenu(); e.Cancel = false; };
            tray.ContextMenuStrip = menu;
            tray.MouseUp += (s, e) =>
            {
                // 左键单击也弹出菜单
                if (e.Button == MouseButtons.Left)
                    typeof(NotifyIcon).GetMethod("ShowContextMenu", BindingFlags.Instance | BindingFlags.NonPublic)
                        ?.Invoke(tray, null);
            };
            UpdateTray();
            tray.Visible = true;

            // 用系统休眠/唤醒通知判断休眠，而不是靠计时器间隔猜测
            SystemEvents.PowerModeChanged += (s, e) =>
            {
                if (e.Mode != PowerModes.Resume) return;
                ui.BeginInvoke(new Action(() =>
                {
                    if (breakEnd != null) return;
                    ResetSit();
                    if (promptKind == PromptKind.Sit) ClosePrompt();
                }));
            };

            timer.Tick += (s, e) => Tick();
            timer.Start();
        }

        // MARK: 计时

        void Tick()
        {
            var now = DateTime.Now;
            var idle = Native.IdleSeconds;
            var away = idle >= Prefs.IdleResetMinutes * 60;

            // 用户离开足够久：视为已经休息
            if (away && breakEnd == null)
            {
                ResetSit();
                if (promptKind == PromptKind.Sit) ClosePrompt();
            }

            if (pausedUntil is DateTime until)
            {
                if (now >= until) { pausedUntil = null; ResetSit(); lastWater = now; }
                else { UpdateTray(); return; }
            }

            // 不在每天的提醒时段内：不提醒，计时从开始时间算起
            if (breakEnd == null && OffHours)
            {
                ResetSit();
                lastWater = now;
                waterSnoozeUntil = null;
                UpdateTray();
                return;
            }

            if (breakEnd is DateTime end)
            {
                var left = (end - now).TotalSeconds;
                if (left <= 0) FinishBreak();
                else if (prompt != null) prompt.MessageLabel.Text = BreakMessage(left);
                UpdateTray();
                return;
            }

            if (prompt == null)
            {
                if (now >= SitDue)
                    ShowSitPrompt();
                else if (Prefs.WaterMinutes > 0 && now >= WaterDue && idle < 120)
                    ShowWaterPrompt(); // 用户在电脑前才提醒喝水，否则等回来再弹
            }
            UpdateTray();
        }

        static int MinuteOfDay => DateTime.Now.Hour * 60 + DateTime.Now.Minute;

        /// 当前是否不在每天的提醒时段内
        static bool OffHours =>
            (Prefs.StartMinute >= 0 && MinuteOfDay < Prefs.StartMinute)
            || (Prefs.EndMinute >= 0 && MinuteOfDay >= Prefs.EndMinute);

        static DateTime Max(DateTime a, DateTime? b) => b is DateTime v && v > a ? v : a;

        DateTime SitDue => Max(sitStart.AddMinutes(Prefs.SitMinutes), sitSnoozeUntil);
        DateTime WaterDue => Max(lastWater.AddMinutes(Prefs.WaterMinutes), waterSnoozeUntil);
        int SatMinutes => (int)(DateTime.Now - sitStart).TotalMinutes;

        void ResetSit()
        {
            sitStart = DateTime.Now;
            sitSnoozeUntil = null;
        }

        // MARK: 提醒动作

        void ShowSitPrompt()
        {
            Show(PromptKind.Sit, "🧍", $"已经坐了 {SatMinutes} 分钟啦",
                 $"{sitTips[random.Next(sitTips.Length)]}\n建议活动 {Prefs.BreakMinutes} 分钟",
                 PromptWindow.MakeButton("开始活动", true, StartBreak),
                 PromptWindow.MakeButton($"{Prefs.SnoozeMinutes} 分钟后", false, () =>
                 {
                     sitSnoozeUntil = DateTime.Now.AddMinutes(Prefs.SnoozeMinutes);
                     ClosePrompt();
                 }),
                 PromptWindow.MakeButton("跳过", false, () => { ResetSit(); ClosePrompt(); }));
        }

        void ShowWaterPrompt()
        {
            Show(PromptKind.Water, "💧", "该喝水了",
                 $"{waterTips[random.Next(waterTips.Length)]}\n今日已喝 {Prefs.WaterToday}/{Prefs.WaterGoal} 杯",
                 PromptWindow.MakeButton("喝好了", true, () => { DrinkWater(); ClosePrompt(); }),
                 PromptWindow.MakeButton($"{Prefs.SnoozeMinutes} 分钟后", false, () =>
                 {
                     waterSnoozeUntil = DateTime.Now.AddMinutes(Prefs.SnoozeMinutes);
                     ClosePrompt();
                 }));
        }

        void StartBreak()
        {
            ClosePrompt();
            pausedUntil = null;
            var end = DateTime.Now.AddMinutes(Prefs.BreakMinutes);
            breakEnd = end;
            Show(PromptKind.OnBreak, "🚶", "活动时间", BreakMessage((end - DateTime.Now).TotalSeconds),
                 new[] { PromptWindow.MakeButton("提前结束", false, FinishBreak) }, sound: false);
        }

        static string BreakMessage(double left)
        {
            var s = Math.Max(0, (int)Math.Ceiling(left));
            return $"剩余 {s / 60:00}:{s % 60:00}\n离开座位走一走，结束时会提醒你";
        }

        void FinishBreak()
        {
            breakEnd = null;
            ResetSit();
            ClosePrompt();
            Show(PromptKind.Done, "✅", "活动完成，继续加油！",
                 $"顺便喝口水吧，今日已喝 {Prefs.WaterToday}/{Prefs.WaterGoal} 杯",
                 PromptWindow.MakeButton("喝了一杯", true, () => { DrinkWater(); ClosePrompt(); }),
                 PromptWindow.MakeButton("好的", false, ClosePrompt));
        }

        void DrinkWater()
        {
            Prefs.WaterToday += 1;
            lastWater = DateTime.Now;
            waterSnoozeUntil = null;
            UpdateTray();
        }

        void Show(PromptKind kind, string emoji, string title, string message, params Button[] buttons) =>
            Show(kind, emoji, title, message, buttons, sound: true);

        void Show(PromptKind kind, string emoji, string title, string message, Button[] buttons, bool sound)
        {
            ClosePrompt();
            var mood = kind == PromptKind.OnBreak ? PetMood.Active : kind == PromptKind.Done ? PetMood.Happy : PetMood.Calm;
            var w = new PromptWindow(emoji, title, message, mood, buttons);
            w.FormClosed += (s, e) =>
            {
                if (prompt != w) return;
                prompt = null;
                promptKind = null;
            };
            prompt = w;
            promptKind = kind;
            w.Show();
            w.Activate();
            if (sound && Prefs.SoundOn) Sounds.Play();
        }

        void ClosePrompt()
        {
            var w = prompt;
            prompt = null;
            promptKind = null;
            w?.Close();
        }

        // MARK: 托盘图标

        void UpdateTray()
        {
            string text, tip;
            Color color;
            if (breakEnd is DateTime end)
            {
                var s = Math.Max(0, (int)Math.Ceiling((end - DateTime.Now).TotalSeconds));
                text = ((s + 59) / 60).ToString();
                color = Color.FromArgb(37, 99, 235);
                tip = $"活动中 {s / 60}:{s % 60:00}";
            }
            else if (pausedUntil != null)
            {
                text = "II";
                color = Color.FromArgb(100, 116, 139);
                tip = "已暂停提醒";
            }
            else if (OffHours)
            {
                text = "z";
                color = Color.FromArgb(100, 116, 139);
                tip = "不在提醒时段";
            }
            else
            {
                var m = SatMinutes;
                text = m.ToString();
                color = m >= Prefs.SitMinutes ? Color.FromArgb(234, 88, 12) : Color.FromArgb(22, 163, 74);
                tip = $"已坐 {m} 分钟";
            }
            tray.Text = "WorkHealth · " + tip;

            var key = text + color.ToArgb();
            if (key == iconKey) return;
            iconKey = key;

            // 图标上直接显示分钟数
            var size = SystemInformation.SmallIconSize;
            using (var bmp = new Bitmap(size.Width, size.Height))
            {
                using (var g = Graphics.FromImage(bmp))
                using (var brush = new SolidBrush(color))
                using (var path = new GraphicsPath())
                using (var font = new Font("Segoe UI", size.Height * (text.Length >= 3 ? 0.45f : text.Length == 2 ? 0.6f : 0.72f),
                                           FontStyle.Bold, GraphicsUnit.Pixel))
                using (var format = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
                {
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
                    float w = size.Width - 1, h = size.Height - 1, r = size.Width / 4f;
                    path.AddArc(0, 0, r * 2, r * 2, 180, 90);
                    path.AddArc(w - r * 2, 0, r * 2, r * 2, 270, 90);
                    path.AddArc(w - r * 2, h - r * 2, r * 2, r * 2, 0, 90);
                    path.AddArc(0, h - r * 2, r * 2, r * 2, 90, 90);
                    path.CloseFigure();
                    g.FillPath(brush, path);
                    g.DrawString(text, font, Brushes.White, new RectangleF(0, 0, size.Width, size.Height + 1), format);
                }
                var handle = bmp.GetHicon();
                var old = tray.Icon;
                tray.Icon = Icon.FromHandle(handle);
                old?.Dispose();
                if (iconHandle != IntPtr.Zero) Native.DestroyIcon(iconHandle);
                iconHandle = handle;
            }
        }

        // MARK: 菜单

        static ToolStripMenuItem Item(string text, Action action, bool check = false)
        {
            var item = new ToolStripMenuItem(text) { Checked = check };
            item.Click += (s, e) => action();
            return item;
        }

        static ToolStripMenuItem Info(string text) => new ToolStripMenuItem(text) { Enabled = false };

        static ToolStripMenuItem Submenu(string title, params ToolStripItem[] items)
        {
            var item = new ToolStripMenuItem(title);
            item.DropDownItems.AddRange(items);
            return item;
        }

        static ToolStripMenuItem Choice(string title, int[] options, int current, Func<int, string> label, Action<int> set) =>
            Submenu($"{title}：{label(current)}",
                    options.Select(v => (ToolStripItem)Item(label(v), () => set(v), v == current)).ToArray());

        static int Mins(TimeSpan t) => Math.Max(0, (int)Math.Ceiling(t.TotalMinutes));

        void BuildMenu()
        {
            menu.Items.Clear();
            var now = DateTime.Now;

            if (breakEnd is DateTime end)
                menu.Items.Add(Info($"🚶 活动中，还剩 {Mins(end - now)} 分钟"));
            else if (pausedUntil is DateTime until)
                menu.Items.Add(Info(until == DateTime.MaxValue ? "⏸ 已暂停提醒" : $"⏸ 已暂停，{Mins(until - now)} 分钟后恢复"));
            else if (OffHours)
            {
                var ended = Prefs.EndMinute >= 0 && MinuteOfDay >= Prefs.EndMinute;
                var s = ended ? $"🌙 已过 {Prefs.Clock(Prefs.EndMinute)}，今天的提醒已结束" : "🌙 还没到开始时间";
                if (Prefs.StartMinute >= 0) s += $" · 每天 {Prefs.Clock(Prefs.StartMinute)} 开始";
                menu.Items.Add(Info(s));
            }
            else
                menu.Items.Add(Info($"🪑 已坐 {SatMinutes} 分钟 · {Mins(SitDue - now)} 分钟后提醒起身"));

            var water = $"💧 今日喝水 {Prefs.WaterToday}/{Prefs.WaterGoal} 杯";
            if (Prefs.WaterMinutes > 0 && breakEnd == null && pausedUntil == null && !OffHours)
                water += $" · {Mins(WaterDue - now)} 分钟后提醒";
            menu.Items.Add(Info(water));
            menu.Items.Add(new ToolStripSeparator());

            if (breakEnd == null) menu.Items.Add(Item($"现在去活动 {Prefs.BreakMinutes} 分钟", StartBreak));
            else menu.Items.Add(Item("结束活动", FinishBreak));
            menu.Items.Add(Item("我喝了一杯水", DrinkWater));
            menu.Items.Add(Item("重置久坐计时", ResetSit));
            menu.Items.Add(new ToolStripSeparator());

            if (pausedUntil != null)
                menu.Items.Add(Item("恢复提醒", () => { pausedUntil = null; ResetSit(); lastWater = DateTime.Now; }));
            else
                menu.Items.Add(Submenu("暂停提醒", new[] { ("30 分钟", 30), ("1 小时", 60), ("2 小时", 120), ("直到手动恢复", 0) }
                    .Select(p => (ToolStripItem)Item(p.Item1, () =>
                    {
                        breakEnd = null;
                        ClosePrompt();
                        pausedUntil = p.Item2 == 0 ? DateTime.MaxValue : DateTime.Now.AddMinutes(p.Item2);
                        UpdateTray();
                    })).ToArray()));

            Func<int, string> minutes = v => $"{v} 分钟";
            menu.Items.Add(Submenu("设置",
                HoursMenu(),
                Choice("久坐提醒", new[] { 25, 30, 45, 60, 90 }, Prefs.SitMinutes, minutes, v => Prefs.SitMinutes = v),
                Choice("每次活动", new[] { 2, 3, 5, 10, 15 }, Prefs.BreakMinutes, minutes, v => Prefs.BreakMinutes = v),
                Choice("喝水提醒", new[] { 0, 20, 30, 45, 60, 90 }, Prefs.WaterMinutes,
                       v => v == 0 ? "关闭" : $"每 {v} 分钟", v => { Prefs.WaterMinutes = v; lastWater = DateTime.Now; }),
                Choice("喝水目标", new[] { 6, 8, 10, 12 }, Prefs.WaterGoal, v => $"{v} 杯/天", v => Prefs.WaterGoal = v),
                Choice("稍后提醒", new[] { 5, 10, 15 }, Prefs.SnoozeMinutes, minutes, v => Prefs.SnoozeMinutes = v),
                Choice("离开多久算休息", new[] { 3, 5, 10 }, Prefs.IdleResetMinutes, minutes, v => Prefs.IdleResetMinutes = v),
                new ToolStripSeparator(),
                SoundMenu(),
                PetMenu(),
                Item("开机自动启动", () => LoginItem.SetEnabled(!LoginItem.IsEnabled), LoginItem.IsEnabled)));

            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(Item("退出", Quit));
        }

        static ToolStripMenuItem HoursMenu()
        {
            Func<int, string> clock = m => m < 0 ? "不限" : Prefs.Clock(m);
            int start = Prefs.StartMinute, end = Prefs.EndMinute;
            var range = start < 0 && end < 0 ? "全天"
                : $"{(start < 0 ? "0:00" : Prefs.Clock(start))}–{(end < 0 ? "24:00" : Prefs.Clock(end))}";
            return Submenu($"提醒时段：{range}",
                Choice("开始", new[] { -1, 420, 450, 480, 510, 540, 570, 600, 630 }, start, clock, v => Prefs.StartMinute = v),
                Choice("结束", new[] { -1, 1020, 1050, 1080, 1110, 1140, 1170, 1200, 1260, 1320 }, end, clock, v => Prefs.EndMinute = v));
        }

        static ToolStripMenuItem SoundMenu()
        {
            var current = Prefs.SoundName;
            var items = new List<ToolStripItem> { Item("关闭", () => Prefs.SoundOn = false, !Prefs.SoundOn), new ToolStripSeparator() };
            foreach (var name in Sounds.Available)
                items.Add(Item(name, () => { Prefs.SoundOn = true; Prefs.SoundName = name; Sounds.Play(name); },
                               Prefs.SoundOn && name == current));
            items.Add(new ToolStripSeparator());
            if (Sounds.IsCustom(current))
                items.Add(Item($"自定义：{Sounds.Label(current)}", () => { Prefs.SoundOn = true; Sounds.Play(current); }, Prefs.SoundOn));
            items.Add(Item("选择音频文件…", PickSoundFile));
            return Submenu($"提示音：{(Prefs.SoundOn ? Sounds.Label(current) : "关闭")}", items.ToArray());
        }

        static ToolStripMenuItem PetMenu()
        {
            var pets = new[] { ("cat", "猫 🐱"), ("dog", "狗 🐶"), ("none", "关闭") };
            var current = pets.FirstOrDefault(p => p.Item1 == Prefs.Pet).Item2 ?? pets[0].Item2;
            return Submenu($"弹窗宠物：{current}",
                           pets.Select(p => (ToolStripItem)Item(p.Item2, () => Prefs.Pet = p.Item1, p.Item1 == Prefs.Pet)).ToArray());
        }

        static void PickSoundFile()
        {
            using (var dialog = new OpenFileDialog { Title = "选择提示音", Filter = "音频文件|*.wav;*.mp3;*.wma;*.m4a|所有文件|*.*" })
            {
                if (dialog.ShowDialog() != DialogResult.OK) return;
                Prefs.SoundOn = true;
                Prefs.SoundName = dialog.FileName;
                Sounds.Play(dialog.FileName);
            }
        }

        void Quit()
        {
            timer.Stop();
            ClosePrompt();
            tray.Visible = false;
            tray.Dispose();
            ExitThread();
        }
    }

    static class Program
    {
        [STAThread]
        static void Main()
        {
            using (new Mutex(true, "WorkHealth-SingleInstance", out var created))
            {
                if (!created) return; // 已经在运行
                Native.SetProcessDPIAware();
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new App());
            }
        }
    }
}
