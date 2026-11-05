// ForeverUI Manager: keeps WoW Forever's addons up to date straight from
// their authors' GitHub releases, and installs Polestar's community guides
// from polestar.guide's signed guide list. No middle man: no account, no
// service of ours in between, no other addon manager. Every download is
// checked against the sha256 its source gives before it goes in AddOns.
//
// Built with the C# compiler that comes with Windows (build.bat). C# 5 only:
// no $"", no ?., no => members.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Numerics;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("ForeverUI Manager")]
[assembly: AssemblyProduct("ForeverUI Manager")]
[assembly: AssemblyDescription("Keeps WoW Forever addons up to date from their GitHub releases")]
[assembly: AssemblyCompany("morderous")]
[assembly: AssemblyVersion("0.3.0.0")]
[assembly: AssemblyFileVersion("0.3.0.0")]

namespace ForeverUIManager
{
    static class Program
    {
        [STAThread]
        static int Main(string[] args)
        {
            Native.SetProcessDPIAware();
            bool hidden = Array.IndexOf(args, "--tray") >= 0;
            bool owned;
            using (Mutex single = new Mutex(true, Core.TestMode ? "ForeverUIManager.Single.Test" : "ForeverUIManager.Single", out owned))
            {
                if (!owned)
                {
                    // Already running: the one open shows itself.
                    Native.PostMessage((IntPtr)0xffff, Native.ShowMe, IntPtr.Zero, IntPtr.Zero);
                    return 0;
                }
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new MainForm(hidden));
                return 0;
            }
        }
    }

    static class Native
    {
        public static readonly int ShowMe = RegisterWindowMessage(Core.TestMode ? "ForeverUIManager.ShowMe.Test" : "ForeverUIManager.ShowMe");

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int RegisterWindowMessage(string message);

        [DllImport("user32.dll")]
        public static extern bool PostMessage(IntPtr hwnd, int msg, IntPtr wparam, IntPtr lparam);

        [DllImport("user32.dll")]
        public static extern bool SetProcessDPIAware();

        [DllImport("user32.dll")]
        public static extern bool DestroyIcon(IntPtr handle);

        [DllImport("dwmapi.dll")]
        public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

        // Windows' dark scroll bars for a list ("DarkMode_Explorer").
        [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)]
        public static extern int SetWindowTheme(IntPtr hwnd, string app, string idList);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr OpenProcess(int access, bool inherit, int pid);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool QueryFullProcessImageName(IntPtr process, int flags, StringBuilder name, ref int size);

        [DllImport("kernel32.dll")]
        public static extern bool CloseHandle(IntPtr handle);

        // The shell's delete with undo (to the Recycle Bin), one layout for
        // 64-bit and one packed for 32-bit.
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct FileOp64
        {
            public IntPtr hwnd;
            public uint wFunc;
            public string pFrom, pTo;
            public ushort fFlags;
            public int fAnyOperationsAborted;
            public IntPtr hNameMappings;
            public string lpszProgressTitle;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode, Pack = 1)]
        public struct FileOp32
        {
            public IntPtr hwnd;
            public uint wFunc;
            public string pFrom, pTo;
            public ushort fFlags;
            public int fAnyOperationsAborted;
            public IntPtr hNameMappings;
            public string lpszProgressTitle;
        }

        [DllImport("shell32.dll", CharSet = CharSet.Unicode, EntryPoint = "SHFileOperationW")]
        public static extern int FileOperation64(ref FileOp64 op);

        [DllImport("shell32.dll", CharSet = CharSet.Unicode, EntryPoint = "SHFileOperationW")]
        public static extern int FileOperation32(ref FileOp32 op);
    }

    // Settings, the log and the app's own folder. FUM_HOME (tests) puts the
    // folder elsewhere and keeps the app off the Windows Run key.
    static class Core
    {
        public const string Version = "0.3.0";
        public const string RunName = "ForeverUIManager";
        public static readonly bool TestMode = !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("FUM_HOME"));
        static string home;
        static Dictionary<string, string> settings;
        static readonly object logLock = new object();

        public static string Env(string name)
        {
            return Environment.GetEnvironmentVariable(name) ?? "";
        }

        public static string Home()
        {
            if (home != null) return home;
            string given = Env("FUM_HOME");
            home = given != "" ? given : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ForeverUIManager");
            Directory.CreateDirectory(home);
            return home;
        }

        public static string Setting(string key, string fallback)
        {
            LoadSettings();
            string value;
            return settings.TryGetValue(key, out value) ? value : fallback;
        }

        public static void SetSetting(string key, string value)
        {
            LoadSettings();
            if (value == null) settings.Remove(key);
            else settings[key] = value;
            List<string> lines = new List<string>();
            foreach (KeyValuePair<string, string> each in settings) lines.Add(each.Key + "=" + each.Value);
            lines.Sort(StringComparer.Ordinal);
            WriteAll(Path.Combine(Home(), "settings.ini"), string.Join("\r\n", lines.ToArray()) + "\r\n");
        }

        static void LoadSettings()
        {
            if (settings != null) return;
            settings = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            string path = Path.Combine(Home(), "settings.ini");
            if (!File.Exists(path)) return;
            foreach (string line in File.ReadAllLines(path))
            {
                int eq = line.IndexOf('=');
                if (eq > 0) settings[line.Substring(0, eq).Trim()] = line.Substring(eq + 1).Trim();
            }
        }

        // Written beside, then swapped in: a crash never leaves half a file.
        public static void WriteAll(string path, string text)
        {
            WriteAll(path, new UTF8Encoding(false).GetBytes(text));
        }

        public static void WriteAll(string path, byte[] bytes)
        {
            string fresh = path + ".new";
            File.WriteAllBytes(fresh, bytes);
            if (File.Exists(path)) File.Replace(fresh, path, null);
            else File.Move(fresh, path);
        }

        public static void Log(string line)
        {
            try
            {
                lock (logLock)
                {
                    string path = Path.Combine(Home(), "log.txt");
                    if (File.Exists(path) && new FileInfo(path).Length > 256 * 1024)
                    {
                        File.Copy(path, path + ".old", true);
                        File.WriteAllText(path, "");
                    }
                    File.AppendAllText(path, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture) + "  " + line + "\r\n");
                }
            }
            catch { }
        }

        // Start with Windows: our own value in the user's Run key, pointing at
        // this exe wherever it is now. Never in a test.
        public static void SetRunKey(bool on)
        {
            if (TestMode) return;
            try
            {
                using (RegistryKey run = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", true))
                {
                    if (run == null) return;
                    string want = "\"" + Application.ExecutablePath + "\" --tray";
                    if (on)
                    {
                        if (!string.Equals(run.GetValue(RunName) as string, want, StringComparison.OrdinalIgnoreCase)) run.SetValue(RunName, want);
                    }
                    else if (run.GetValue(RunName) != null) run.DeleteValue(RunName, false);
                }
            }
            catch (Exception why) { Log("Run key: " + why.Message); }
        }

        public static string Hex(byte[] bytes)
        {
            return BitConverter.ToString(bytes).Replace("-", "").ToLowerInvariant();
        }

        public static string Sha256Of(string path)
        {
            using (FileStream input = File.OpenRead(path))
            using (SHA256 hash = SHA256.Create())
                return Hex(hash.ComputeHash(input));
        }

        public static string Sha256Of(byte[] bytes)
        {
            using (SHA256 hash = SHA256.Create())
                return Hex(hash.ComputeHash(bytes));
        }

        public static string Bytes(long bytes)
        {
            CultureInfo c = CultureInfo.InvariantCulture;
            if (bytes >= 1073741824) return (bytes / 1073741824.0).ToString("0.00", c) + " GB";
            return bytes >= 1048576 ? (bytes / 1048576.0).ToString("0.0", c) + " MB" : (bytes / 1024.0).ToString("0.0", c) + " KB";
        }

        // "0.3.1" against "0.2.5": the numbers of each part in turn.
        public static int CompareVersions(string a, string b)
        {
            string[] x = Regex.Split((a ?? "").TrimStart('v', 'V'), @"[.\-+ ]"), y = Regex.Split((b ?? "").TrimStart('v', 'V'), @"[.\-+ ]");
            for (int i = 0; i < Math.Max(x.Length, y.Length); i++)
            {
                long m = 0, n = 0;
                if (i < x.Length) long.TryParse(Regex.Match(x[i], @"^\d+").Value, out m);
                if (i < y.Length) long.TryParse(Regex.Match(y[i], @"^\d+").Value, out n);
                if (m != n) return m < n ? -1 : 1;
            }
            return 0;
        }
    }

    static class Json
    {
        static JavaScriptSerializer Serializer()
        {
            JavaScriptSerializer serializer = new JavaScriptSerializer();
            serializer.MaxJsonLength = int.MaxValue;
            return serializer;
        }

        public static object Parse(string text) { return Serializer().DeserializeObject(text); }
        public static string Write(object value) { return Serializer().Serialize(value); }

        public static string Str(Dictionary<string, object> d, string key)
        {
            object value;
            return d != null && d.TryGetValue(key, out value) && value != null && !(value is Dictionary<string, object>) && !(value is object[])
                ? Convert.ToString(value, CultureInfo.InvariantCulture) : null;
        }

        public static bool Bool(Dictionary<string, object> d, string key)
        {
            object value;
            return d != null && d.TryGetValue(key, out value) && value is bool && (bool)value;
        }

        public static long Long(Dictionary<string, object> d, string key)
        {
            object value;
            if (d != null && d.TryGetValue(key, out value) && value != null && !(value is string))
                try { return Convert.ToInt64(value, CultureInfo.InvariantCulture); } catch { }
            return -1;
        }

        public static object[] Arr(Dictionary<string, object> d, string key)
        {
            object value;
            if (d == null || !d.TryGetValue(key, out value)) return new object[0];
            if (value is object[]) return (object[])value;
            if (value is System.Collections.ArrayList) return ((System.Collections.ArrayList)value).ToArray();
            return new object[0];
        }

        public static Dictionary<string, object> Obj(Dictionary<string, object> d, string key)
        {
            object value;
            return d != null && d.TryGetValue(key, out value) ? value as Dictionary<string, object> : null;
        }
    }

    // What the app knows about some repositories beforehand: one that ships
    // several things (Polestar: the addon in its v* releases, its library,
    // tools and data in others) says which release and zip is the addon.
    // The ForeverUI pack's pack.json says it for its own; these lists are
    // the app's own, for when it has never read the pack.
    class KnownRepo
    {
        public string Repo, Title, Series, Zip;
        public bool Guide, Betas;
        public bool Required;           // the pack's: always on the list, cannot be taken off
        public bool Ticked = true;      // the pack's: comes ticked (a big one does not)

        public string Key { get { return TrackedAddon.KeyOf(Repo, Series); } }

        public static readonly KnownRepo[] All =
        {
            new KnownRepo { Repo = "EllesmereGaming/EllesmereUI", Title = "EllesmereUI" },
            new KnownRepo { Repo = "fitzforge/polestar", Title = "Polestar", Series = @"^v\d", Zip = "Polestar-*.zip" },
        };

        // Polestar guides published on GitHub, looked at before going on the
        // list (2026-11-04): each release a zip of PolestarPack_ folders, its
        // licence followed (the three conversions keep their originals').
        public static readonly KnownRepo[] Guides =
        {
            new KnownRepo { Repo = "petllama/lodestar-guides", Title = "Lodestar Guides", Guide = true },
            new KnownRepo { Repo = "petllama/mittenquest-guides", Title = "MittenQuest Guides", Guide = true },
            new KnownRepo { Repo = "petllama/rxp-free-guides", Title = "Free RestedXP Guides", Guide = true },
            new KnownRepo { Repo = "bmagic/every-quest", Title = "Every Quest", Guide = true },
            new KnownRepo { Repo = "AurumTitanos/Aurums-Night-Elf-Druid-Guide", Title = "Aurum's Night Elf Druid Guide", Guide = true, Betas = true },
        };

        // The addons and guides offered now: the pack's, else the app's own.
        public static KnownRepo[] Addons() { return Pack.Addons ?? All; }
        public static KnownRepo[] GuideRepos() { return Pack.Guides ?? Guides; }

        // A repository's first entry (for one with several series, the
        // first is its main thing: Spoken before its voice packs).
        public static KnownRepo Of(string repo)
        {
            return Addons().Concat(GuideRepos()).FirstOrDefault(k => string.Equals(k.Repo, repo, StringComparison.OrdinalIgnoreCase));
        }
    }

    // The ForeverUI pack: the addons and guides of the ForeverUI look, as
    // pack.json in the ForeverUI repository lists them (raw.githubusercontent.com,
    // counted in no limit of GitHub's API). The copy last read is kept in
    // the app's folder for when GitHub does not answer. FUM_PACK (tests): a
    // file or an address read instead; "off" reads nothing new.
    static class Pack
    {
        public const string Repo = "morderous/foreverui";
        public static KnownRepo[] Addons, Guides;   // null: never read
        public static string Text;                 // the pack.json in use

        static string HeldPath() { return Path.Combine(Core.Home(), "pack.json"); }

        public static string Url
        {
            get
            {
                string given = Core.Env("FUM_PACK");
                return given != "" ? given : "https://raw.githubusercontent.com/" + Repo + "/main/pack.json";
            }
        }

        // At start: the copy kept, if any.
        public static void LoadHeld()
        {
            string path = HeldPath();
            if (!File.Exists(path)) return;
            try { Use(File.ReadAllText(path, Encoding.UTF8), false); }
            catch (Exception why) { Core.Log("pack.json kept: " + why.Message); }
        }

        // pack.json from the repository, as text. Throws, saying why.
        public static string Download()
        {
            string url = Url;
            if (url == "off") throw new Exception("not read in this test");
            if (!url.StartsWith("https://", StringComparison.OrdinalIgnoreCase) && !url.StartsWith("http://", StringComparison.OrdinalIgnoreCase))
                return File.ReadAllText(url, Encoding.UTF8);
            return Net.Text(url);
        }

        // A pack.json read (now or at start) put in use, and kept when new.
        // True when it changed what the pack lists.
        public static bool Use(string text, bool keep)
        {
            KnownRepo[][] read = Parse(text);
            bool changed = Text == null || Text != text;
            Addons = read[0];
            Guides = read[1];
            Text = text;
            if (keep && changed)
                try { Core.WriteAll(HeldPath(), text); }
                catch (Exception why) { Core.Log("pack.json not kept: " + why.Message); }
            return changed;
        }

        // { "format": 1, "addons": [ { "repo", "title", "required", "ticked",
        // "series", "zip" } ], "guides": [ { "repo", "title", "betas" } ] }.
        // An entry that cannot be taken is left out; a pack with no addon
        // at all is refused.
        public static KnownRepo[][] Parse(string text)
        {
            Dictionary<string, object> top = Json.Parse(text) as Dictionary<string, object>;
            if (top == null) throw new Exception("pack.json is not a JSON object");
            if (Json.Long(top, "format") != 1) throw new Exception("pack.json is of a format this version does not read (" + Json.Str(top, "format") + ")");
            List<KnownRepo> addons = new List<KnownRepo>(), guides = new List<KnownRepo>();
            foreach (object each in Json.Arr(top, "addons"))
            {
                KnownRepo k = Entry(each as Dictionary<string, object>, false);
                if (k != null && !addons.Exists(o => o.Key == k.Key)) addons.Add(k);
            }
            foreach (object each in Json.Arr(top, "guides"))
            {
                KnownRepo k = Entry(each as Dictionary<string, object>, true);
                if (k != null && !guides.Exists(o => string.Equals(o.Repo, k.Repo, StringComparison.OrdinalIgnoreCase))) guides.Add(k);
            }
            if (addons.Count == 0) throw new Exception("pack.json lists no addon");
            return new[] { addons.ToArray(), guides.ToArray() };
        }

        static KnownRepo Entry(Dictionary<string, object> d, bool guide)
        {
            string repo = GitHub.ParseRepo(Json.Str(d, "repo"));
            if (repo == null) return null;
            string title = Json.Str(d, "title"), series = Json.Str(d, "series"), zip = Json.Str(d, "zip");
            if (title != null) title = Regex.Replace(title, @"[\x00-\x1f]", "").Trim();
            if (title == "" || (title != null && title.Length > 80)) title = null;
            if (series != null)
                try { new Regex(series); }
                catch (ArgumentException) { Core.Log("pack.json: " + repo + "'s series is not a pattern: " + series); return null; }
            if (zip != null && (zip.IndexOfAny(new[] { '/', '\\' }) >= 0 || !zip.EndsWith(".zip", StringComparison.OrdinalIgnoreCase))) return null;
            KnownRepo k = new KnownRepo { Repo = repo, Title = title, Series = series, Zip = zip, Guide = guide };
            if (guide) k.Betas = Json.Bool(d, "betas");
            else
            {
                k.Required = Json.Bool(d, "required");
                k.Ticked = k.Required || !d.ContainsKey("ticked") || Json.Bool(d, "ticked");
            }
            return k;
        }
    }

    // An addon on the list: from a GitHub repository, or a community guide
    // from polestar.guide. Kept in addons.json, never sent anywhere.
    class TrackedAddon
    {
        public string Kind = "github";  // or "pack"
        public string Repo;             // owner/name; "pack:<id>" for a guide
        public string Series;           // the tags of its releases (a pattern), when the repository ships several things
        public string ZipPattern;       // its zip's name ("Polestar-*.zip")
        public string Tag;              // the version installed by us; null when not
        public string Asset;
        public string[] Folders;        // the folders we put in AddOns
        public string InstalledAt;
        public bool Auto = true;        // updates by itself when a new version comes out
        public bool Trusted;            // the warning before the first install was said yes to
        public string Known;            // the newest version seen
        public string Title;
        public bool Guide;              // a Polestar guide from GitHub: shown with the guides
        public bool Betas;              // test versions (pre-releases) too
        public bool Want = true;        // ticked: Install all puts it in (one not installed)

        // A guide's own: its id, and what it was installed as (pinned).
        public string PackId, Uid, PublisherId, PublisherHandle, Author, Pulled;

        // Not kept: this run's look.
        public Release Latest;
        public PackEntry Entry;         // the guide list's word on it
        public string Problem;          // why the last check failed
        public string Found;            // its version, when it is in AddOns but not put there by us
        public bool Missing;            // some of its folders are gone from AddOns
        public string Interface;        // its .toc's Interface line
        public string Busy;             // "Downloading 40%"
        public string Source;           // not added by hand: "pack" (an addon of the ForeverUI pack); a GitHub guide's "list" (ours) or "search"
        public string Code;             // what an installed guide holds besides what Polestar's compiler makes
        public bool Required;           // the pack's word, read again at each start: cannot be taken off

        public bool IsPack { get { return Kind == "pack"; } }

        // One entry per repository and series: Spoken and each of its voice
        // packs come from one repository. "owner/name", or "owner/name <series>"
        // with the series escaped (no space or comma in it).
        public static string KeyOf(string repo, string series)
        {
            return series == null ? repo : repo + " " + Uri.EscapeDataString(series);
        }

        public string Key { get { return KeyOf(Repo, Series); } }

        // The same repository (in any case) and the same series (exactly).
        public static bool SameKey(string a, string b)
        {
            if (a == null || b == null) return false;
            int x = a.IndexOf(' '), y = b.IndexOf(' ');
            string ra = x < 0 ? a : a.Substring(0, x), rb = y < 0 ? b : b.Substring(0, y);
            string sa = x < 0 ? null : a.Substring(x + 1), sb = y < 0 ? null : b.Substring(y + 1);
            return string.Equals(ra, rb, StringComparison.OrdinalIgnoreCase) && sa == sb;
        }

        public bool Is(KnownRepo k) { return !IsPack && SameKey(Key, k.Key); }

        // An addon of the pack, new on the list: ticked as the pack says; a
        // big one (not ticked) does not update by itself either.
        public static TrackedAddon ForItem(KnownRepo k)
        {
            TrackedAddon a = new TrackedAddon { Repo = k.Repo, Source = "pack" };
            a.Take(k);
            a.Want = k.Ticked;
            a.Auto = k.Ticked;
            return a;
        }

        // The pack's word on an addon on the list. True when something kept changed.
        public bool Take(KnownRepo k)
        {
            bool changed = Series != k.Series || ZipPattern != k.Zip || Source != "pack" || (k.Title != null && Title != k.Title);
            Series = k.Series;
            ZipPattern = k.Zip;
            if (k.Title != null) Title = k.Title;
            Source = "pack";
            Required = k.Required;
            if (Required) Want = true;
            return changed;
        }
        public bool WithGuides { get { return IsPack || Guide; } }

        public string RepoName
        {
            get
            {
                if (IsPack) return Packs.MainFolder(PackId);
                int slash = Repo.IndexOf('/');
                return slash >= 0 ? Repo.Substring(slash + 1) : Repo;
            }
        }

        public string Name
        {
            get { return !string.IsNullOrEmpty(Title) ? Title : IsPack ? PackId : RepoName; }
        }

        public string By
        {
            get
            {
                if (IsPack) return Author ?? PublisherHandle ?? "";
                int slash = Repo.IndexOf('/');
                return slash > 0 ? Repo.Substring(0, slash) : "";
            }
        }

        public bool UpdateWaits
        {
            get { return Tag != null && Known != null && Known != Tag; }
        }

        public static TrackedAddon ForRepo(string repo)
        {
            TrackedAddon a = new TrackedAddon { Repo = repo };
            KnownRepo known = KnownRepo.Of(repo);
            if (known != null)
            {
                a.Repo = known.Repo;
                a.Title = known.Title;
                a.Series = known.Series;
                a.ZipPattern = known.Zip;
                a.Guide = known.Guide;
                a.Betas = known.Betas;
                if (known.Guide) a.Source = "list";
            }
            return a;
        }

        public static TrackedAddon ForPack(PackEntry entry)
        {
            TrackedAddon a = new TrackedAddon { Kind = "pack", Repo = "pack:" + entry.Id, PackId = entry.Id, Auto = false };
            a.Show(entry);
            return a;
        }

        // The guide list's entry on this guide: its newest version.
        public void Show(PackEntry entry)
        {
            Entry = entry;
            Title = entry.Title;
            Author = entry.Author;
            Latest = entry.AsRelease();
            Known = entry.Version;
        }
    }

    static class Store
    {
        static string FilePath() { return Path.Combine(Core.Home(), "addons.json"); }

        public static List<TrackedAddon> Load()
        {
            List<TrackedAddon> list = new List<TrackedAddon>();
            string path = FilePath();
            if (File.Exists(path))
            {
                try
                {
                    Dictionary<string, object> top = Json.Parse(File.ReadAllText(path)) as Dictionary<string, object>;
                    foreach (object each in Json.Arr(top, "addons"))
                    {
                        TrackedAddon a = Row(each as Dictionary<string, object>);
                        if (a != null) list.Add(a);
                    }
                }
                catch (Exception why)
                {
                    // A list that cannot be read is kept as it is, never written over.
                    Core.Log("addons.json unreadable: " + why.Message);
                    try { File.Copy(path, path + ".unreadable-" + DateTime.Now.ToString("yyyyMMdd-HHmmss")); } catch { }
                    return list;
                }
            }
            bool fresh = !File.Exists(path);
            if (Seed(list).Count == 0 && fresh) Save(list);
            return list;
        }

        // The pack's addons (the app's own two, when it has never read the
        // pack) on the list, each offered once: one taken off stays off; a
        // required one always comes back. The ones the list has take the
        // pack's word (series, zip, title, required). Returns the ones added.
        public static List<TrackedAddon> Seed(List<TrackedAddon> list)
        {
            List<TrackedAddon> added = new List<TrackedAddon>();
            if (Core.Env("FUM_NO_SEED") == "1") return added;
            List<string> offered = OfferedKeys();
            bool changed = false, offeredMore = false;
            KnownRepo[] items = KnownRepo.Addons();
            foreach (TrackedAddon a in list) a.Required = false;
            foreach (KnownRepo k in items)
            {
                TrackedAddon have = Match(list, k);
                if (have != null) changed |= have.Take(k);
                else if (k.Required || !Offered(offered, k))
                {
                    TrackedAddon a = TrackedAddon.ForItem(k);
                    list.Add(a);
                    added.Add(a);
                }
                if (!Offered(offered, k)) { offered.Add(k.Key); offeredMore = true; }
            }
            // In the pack's order (ForeverUI first), the others after, as they were.
            List<TrackedAddon> before = new List<TrackedAddon>(list);
            Func<TrackedAddon, int> place = a => { int i = Array.FindIndex(items, k => a.Is(k)); return i >= 0 ? i : items.Length + before.IndexOf(a); };
            List<TrackedAddon> ordered = list.OrderBy(place).ToList();
            if (!ordered.SequenceEqual(before)) { list.Clear(); list.AddRange(ordered); changed = true; }
            if (changed || added.Count > 0) Save(list);
            if (offeredMore) Core.SetSetting("starters", string.Join(",", offered.ToArray()));
            return added;
        }

        // The entry on the list for a pack item: the same repository and
        // series; else one of the same repository with no series, which
        // installed a zip of the item's name (Spoken, added by hand before
        // the pack named its series).
        static TrackedAddon Match(List<TrackedAddon> list, KnownRepo k)
        {
            TrackedAddon same = list.Find(a => a.Is(k));
            if (same != null || k.Series == null) return same;
            return list.Find(a => !a.IsPack && !a.Guide && a.Series == null && string.Equals(a.Repo, k.Repo, StringComparison.OrdinalIgnoreCase)
                && (k.Zip == null || a.Asset == null || GitHub.Like(a.Asset, k.Zip))
                && !KnownRepo.Addons().Any(o => o.Series == null && a.Is(o)));
        }

        public static List<string> OfferedKeys()
        {
            return Core.Setting("starters", "").Split(',').Where(s => s != "").ToList();
        }

        // Offered before: its key; or, from before the pack, the repository
        // alone, for the series the app knew it by (Polestar's).
        public static bool Offered(List<string> offered, KnownRepo k)
        {
            if (offered.Exists(o => TrackedAddon.SameKey(o, k.Key))) return true;
            KnownRepo builtIn = KnownRepo.All.FirstOrDefault(b => string.Equals(b.Repo, k.Repo, StringComparison.OrdinalIgnoreCase));
            return builtIn != null && builtIn.Series == k.Series && offered.Contains(k.Repo, StringComparer.OrdinalIgnoreCase);
        }

        static TrackedAddon Row(Dictionary<string, object> d)
        {
            TrackedAddon a;
            if (Json.Str(d, "kind") == "pack")
            {
                string id = Json.Str(d, "id");
                if (!Packs.ValidId(id)) return null;
                a = new TrackedAddon { Kind = "pack", Repo = "pack:" + id, PackId = id };
                a.Uid = Json.Str(d, "uid");
                a.PublisherId = Json.Str(d, "publisherId");
                a.PublisherHandle = Json.Str(d, "publisherHandle");
                a.Author = Json.Str(d, "author");
                a.Pulled = Json.Str(d, "pulled");
            }
            else
            {
                string repo = GitHub.ParseRepo(Json.Str(d, "repo"));
                if (repo == null) return null;
                a = TrackedAddon.ForRepo(repo);
                if (Json.Str(d, "series") != null) a.Series = Json.Str(d, "series");
                if (Json.Str(d, "zip") != null) a.ZipPattern = Json.Str(d, "zip");
                if (d.ContainsKey("guide")) a.Guide = Json.Bool(d, "guide");
                if (d.ContainsKey("betas")) a.Betas = Json.Bool(d, "betas");
                if (Json.Str(d, "source") != null) a.Source = Json.Str(d, "source");
            }
            a.Tag = Json.Str(d, "tag");
            a.Asset = Json.Str(d, "asset");
            a.InstalledAt = Json.Str(d, "installedAt");
            a.Known = Json.Str(d, "known");
            if (Json.Str(d, "title") != null) a.Title = Json.Str(d, "title");
            a.Auto = d.ContainsKey("auto") ? Json.Bool(d, "auto") : !a.IsPack;
            a.Want = !d.ContainsKey("want") || Json.Bool(d, "want");
            a.Trusted = Json.Bool(d, "trusted");
            List<string> folders = new List<string>();
            foreach (object f in Json.Arr(d, "folders"))
                if (f is string && Installer.SafeFolder((string)f)) folders.Add((string)f);
            a.Folders = folders.Count > 0 ? folders.ToArray() : null;
            if (a.Folders == null) a.Tag = null;
            return a;
        }

        public static void Save(List<TrackedAddon> list)
        {
            List<object> rows = new List<object>();
            foreach (TrackedAddon a in list)
            {
                Dictionary<string, object> d = new Dictionary<string, object>();
                if (a.IsPack)
                {
                    d["kind"] = "pack";
                    d["id"] = a.PackId;
                    if (a.Uid != null) d["uid"] = a.Uid;
                    if (a.PublisherId != null) d["publisherId"] = a.PublisherId;
                    if (a.PublisherHandle != null) d["publisherHandle"] = a.PublisherHandle;
                    if (a.Author != null) d["author"] = a.Author;
                    if (a.Pulled != null) d["pulled"] = a.Pulled;
                }
                else
                {
                    d["repo"] = a.Repo;
                    if (a.Series != null) d["series"] = a.Series;
                    if (a.ZipPattern != null) d["zip"] = a.ZipPattern;
                    if (a.Guide) d["guide"] = true;
                    if (a.Betas) d["betas"] = true;
                    if (a.Source != null) d["source"] = a.Source;
                }
                if (a.Tag != null) d["tag"] = a.Tag;
                if (a.Asset != null) d["asset"] = a.Asset;
                if (a.Folders != null) d["folders"] = a.Folders;
                if (a.InstalledAt != null) d["installedAt"] = a.InstalledAt;
                if (a.Known != null) d["known"] = a.Known;
                if (!string.IsNullOrEmpty(a.Title)) d["title"] = a.Title;
                d["auto"] = a.Auto;
                if (!a.Want) d["want"] = false;
                d["trusted"] = a.Trusted;
                rows.Add(d);
            }
            Dictionary<string, object> top = new Dictionary<string, object>();
            top["format"] = 1;
            top["addons"] = rows;
            try { Core.WriteAll(FilePath(), Json.Write(top)); }
            catch (Exception why) { Core.Log("addons.json not saved: " + why.Message); }
        }
    }

    // WoW Forever on this computer: Battle.net puts it beside retail, in
    // World of Warcraft\_forever_, marked "wowf" in its .flavor.info.
    static class Game
    {
        public static string Folder()
        {
            string given = Core.Env("FUM_GAME");
            if (given != "") return given;
            string picked = Core.Setting("game", "");
            if (IsForever(picked)) return picked;
            foreach (string wow in WowFolders())
            {
                string forever = Path.Combine(wow, "_forever_");
                if (IsForever(forever)) return forever;
            }
            return null;
        }

        public static bool IsForever(string folder)
        {
            if (string.IsNullOrEmpty(folder) || !Directory.Exists(folder) || !File.Exists(Path.Combine(folder, "Wow.exe"))) return false;
            string flavor = Path.Combine(folder, ".flavor.info");
            if (File.Exists(flavor))
            {
                try { return Regex.IsMatch(File.ReadAllText(flavor), @"(^|\s)wowf(\s|$)"); } catch { }
            }
            return string.Equals(Path.GetFileName(folder.TrimEnd('\\')), "_forever_", StringComparison.OrdinalIgnoreCase);
        }

        static IEnumerable<string> WowFolders()
        {
            List<string> found = new List<string>();
            try
            {
                using (RegistryKey key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\World of Warcraft"))
                    if (key != null && key.GetValue("InstallLocation") is string) found.Add((string)key.GetValue("InstallLocation"));
                using (RegistryKey key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft"))
                    if (key != null && key.GetValue("InstallPath") is string)
                    {
                        string path = ((string)key.GetValue("InstallPath")).TrimEnd('\\');
                        found.Add(Path.GetFileName(path).StartsWith("_") ? Path.GetDirectoryName(path) : path);
                    }
            }
            catch { }
            found.Add(@"C:\Program Files (x86)\World of Warcraft");
            found.Add(@"C:\Program Files\World of Warcraft");
            foreach (DriveInfo drive in DriveInfo.GetDrives())
            {
                if (drive.DriveType != DriveType.Fixed) continue;
                found.Add(Path.Combine(drive.Name, "World of Warcraft"));
                found.Add(Path.Combine(drive.Name, @"Games\World of Warcraft"));
                found.Add(Path.Combine(drive.Name, @"Program Files (x86)\World of Warcraft"));
            }
            return found.Distinct(StringComparer.OrdinalIgnoreCase);
        }

        public static string AddOns(string game)
        {
            return game == null ? null : Path.Combine(game, @"Interface\AddOns");
        }

        // Its version, from Battle.net's .build.info one folder up.
        public static string Version(string game)
        {
            string given = Core.Env("FUM_GAME_VERSION");
            if (given != "") return given;
            try
            {
                string info = Path.Combine(Path.GetDirectoryName(game.TrimEnd('\\')), ".build.info");
                if (!File.Exists(info)) return "";
                string[] lines = File.ReadAllLines(info);
                if (lines.Length < 2) return "";
                string[] heads = lines[0].Split('|');
                int product = -1, version = -1;
                for (int i = 0; i < heads.Length; i++)
                {
                    if (heads[i].StartsWith("Product!")) product = i;
                    if (heads[i].StartsWith("Version!")) version = i;
                }
                if (product < 0 || version < 0) return "";
                for (int n = 1; n < lines.Length; n++)
                {
                    string[] cells = lines[n].Split('|');
                    if (cells.Length > Math.Max(product, version) && cells[product] == "wowf") return cells[version];
                }
            }
            catch { }
            return "";
        }

        // Its Interface number, as a .toc says it: 1.60.1 is 16001. 0 when unknown.
        public static int Interface(string game)
        {
            Match v = Regex.Match(Version(game), @"^(\d+)\.(\d+)\.(\d+)");
            return v.Success ? int.Parse(v.Groups[1].Value) * 10000 + int.Parse(v.Groups[2].Value) * 100 + int.Parse(v.Groups[3].Value) : 0;
        }

        // Is WoW Forever open? A Wow.exe started from its folder. One whose
        // path cannot be read counts as open, to be safe.
        public static bool Running(string game)
        {
            if (Core.Env("FUM_TEST_RUNNING") == "1") return true;
            if (game == null) return false;
            string inside = Path.GetFullPath(game).TrimEnd('\\') + "\\";
            foreach (Process process in Process.GetProcessesByName("Wow"))
            {
                using (process)
                {
                    string path = ImagePath(process.Id);
                    if (path == null || path.StartsWith(inside, StringComparison.OrdinalIgnoreCase)) return true;
                }
            }
            return false;
        }

        static string ImagePath(int pid)
        {
            IntPtr handle = Native.OpenProcess(0x1000, false, pid);   // PROCESS_QUERY_LIMITED_INFORMATION
            if (handle == IntPtr.Zero) return null;
            try
            {
                StringBuilder name = new StringBuilder(1024);
                int size = name.Capacity;
                return Native.QueryFullProcessImageName(handle, 0, name, ref size) ? name.ToString(0, size) : null;
            }
            finally { Native.CloseHandle(handle); }
        }
    }

    class Release
    {
        public string Repo, Tag, Published, Notes, PageUrl;
        public string ZipName, ZipUrl, Sha256, PickedBy;
        public long Size = -1;
        public string Origin;           // downloads only from here (a guide: polestar.guide)
        public long Cap;                // and no bigger than this
        public bool Test;               // a pre-release
    }

    class Asset
    {
        public string Name, Url, Sha256;
        public long Size = -1;
    }

    // GitHub's API is out for now (its limit of 60 an hour, or no answer):
    // its web pages are asked instead.
    class ApiOut : Exception { public ApiOut(string message) : base(message) { } }

    // An answer for good: no repository, no release, no build for Forever.
    class Final : Exception { public Final(string message) : base(message) { } }

    static class Net
    {
        public static string Agent { get { return "ForeverUI-Manager/" + Core.Version; } }

        public static HttpWebRequest Make(string url)
        {
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
            HttpWebRequest request = (HttpWebRequest)WebRequest.Create(url);
            request.UserAgent = Agent;
            request.Timeout = 20000;
            request.ReadWriteTimeout = 60000;
            request.AllowAutoRedirect = true;
            return request;
        }

        public static byte[] ReadCapped(Stream input, long cap)
        {
            using (MemoryStream output = new MemoryStream())
            {
                byte[] buffer = new byte[16384];
                int read;
                while ((read = input.Read(buffer, 0, buffer.Length)) > 0)
                {
                    output.Write(buffer, 0, read);
                    if (output.Length > cap) throw new Exception("the answer is bigger than " + (cap / 1024) + " KB");
                }
                return output.ToArray();
            }
        }

        // A small file (release.json, SHA256SUMS) as text. 404: Final.
        public static string Text(string url)
        {
            try
            {
                using (HttpWebResponse response = (HttpWebResponse)Make(url).GetResponse())
                using (Stream input = response.GetResponseStream())
                    return Encoding.UTF8.GetString(ReadCapped(input, 1024 * 1024));
            }
            catch (WebException error)
            {
                if (IsMissing(error, url)) throw new Final("not found: " + url);
                throw;
            }
        }

        // Where an address ends after its redirects.
        public static string Landing(string url)
        {
            HttpWebRequest request = Make(url);
            request.Method = "HEAD";
            try
            {
                using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
                    return response.ResponseUri.AbsoluteUri;
            }
            catch (WebException error)
            {
                if (IsMissing(error, null)) throw new Final("GitHub has no repository by that name");
                throw;
            }
        }

        // GitHub sometimes closes the connection in a missing page's body, so
        // .NET sees no response: its head alone tells the 404.
        public static bool IsMissing(WebException error, string url)
        {
            HttpWebResponse response = error.Response as HttpWebResponse;
            if (response != null)
                using (response)
                    return response.StatusCode == HttpStatusCode.NotFound;
            if (url == null) return false;
            HttpWebRequest head = Make(url);
            head.Method = "HEAD";
            try { head.GetResponse().Close(); return false; }
            catch (WebException again)
            {
                HttpWebResponse second = again.Response as HttpWebResponse;
                if (second == null) return false;
                using (second) return second.StatusCode == HttpStatusCode.NotFound;
            }
        }

        public static bool SameOrigin(string url, string origin)
        {
            Uri a, b;
            return Uri.TryCreate(url, UriKind.Absolute, out a) && Uri.TryCreate(origin, UriKind.Absolute, out b)
                && a.Scheme == b.Scheme && string.Equals(a.Host, b.Host, StringComparison.OrdinalIgnoreCase) && a.Port == b.Port;
        }

        // A download to a file. With an origin, every redirect must stay on
        // it (a guide's zip comes from polestar.guide and nowhere else); with
        // a cap, nothing bigger is taken.
        public static void Download(string url, string path, Action<long, long> progress, string origin, long cap)
        {
            Download(url, path, progress, origin, cap, false);
        }

        // Resume: what path holds already is kept and only the rest asked
        // for (a Range); a download that stops is taken up again where it
        // stopped, three times, a few seconds apart.
        public static void Download(string url, string path, Action<long, long> progress, string origin, long cap, bool resume)
        {
            for (int attempt = 0; ; attempt++)
            {
                try { Once(url, path, progress, origin, cap, resume); return; }
                catch (Exception why)
                {
                    if (why is Final || !resume || attempt >= 3 || why.Message.Contains("bigger than")) throw;
                    Core.Log("download stopped (" + why.Message + "), taken up again at " + (File.Exists(path) ? new FileInfo(path).Length : 0) + " bytes");
                    Thread.Sleep(Core.TestMode ? 200 : 3000 * (attempt + 1));
                }
            }
        }

        static void Once(string url, string path, Action<long, long> progress, string origin, long cap, bool resume)
        {
            long have = resume && File.Exists(path) ? new FileInfo(path).Length : 0;
            string at = url;
            for (int hop = 0; ; hop++)
            {
                if (origin != null && !SameOrigin(at, origin)) throw new Final("its download is not on " + origin);
                if (hop > 5) throw new Exception("its download goes round in redirects");
                HttpWebRequest request = Make(at);
                request.AllowAutoRedirect = origin == null;
                if (have > 0) request.AddRange(have);
                try
                {
                    using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
                    {
                        int code = (int)response.StatusCode;
                        if (code >= 300 && code < 400)
                        {
                            string location = response.Headers["Location"];
                            if (string.IsNullOrEmpty(location)) throw new Exception("its download moved without saying where");
                            at = new Uri(new Uri(at), location).AbsoluteUri;
                            continue;
                        }
                        // 206: the rest, after what is held; 200: all of it again.
                        bool rest = have > 0 && code == 206;
                        if (rest)
                        {
                            Match from = Regex.Match(response.Headers["Content-Range"] ?? "", @"^bytes (\d+)-");
                            if (!from.Success || long.Parse(from.Groups[1].Value) != have) throw new Exception("its download came back from the wrong place");
                        }
                        long start = rest ? have : 0;
                        long total = response.ContentLength >= 0 ? start + response.ContentLength : -1, done = start;
                        if (cap > 0 && total > cap) throw new Exception("its download is bigger than " + (cap / 1048576) + " MB");
                        using (Stream input = response.GetResponseStream())
                        using (FileStream output = rest ? new FileStream(path, FileMode.Append, FileAccess.Write) : File.Create(path))
                        {
                            byte[] buffer = new byte[81920];
                            int read;
                            DateTime shown = DateTime.MinValue;
                            while ((read = input.Read(buffer, 0, buffer.Length)) > 0)
                            {
                                output.Write(buffer, 0, read);
                                done += read;
                                if (cap > 0 && done > cap) throw new Exception("its download is bigger than " + (cap / 1048576) + " MB");
                                if (progress != null && (DateTime.Now - shown).TotalMilliseconds > 150)
                                {
                                    shown = DateTime.Now;
                                    progress(done, total);
                                }
                            }
                        }
                        if (progress != null) progress(done, total);
                        if (total > 0 && done != total) throw new Exception("the download stopped early");
                        return;
                    }
                }
                catch (WebException error)
                {
                    // 416: nothing after what is held. Whole already when the
                    // server says it is that big; else started again.
                    HttpWebResponse said = error.Response as HttpWebResponse;
                    if (have > 0 && said != null && (int)said.StatusCode == 416)
                    {
                        Match whole = Regex.Match(said.Headers["Content-Range"] ?? "", @"/(\d+)$");
                        said.Close();
                        if (whole.Success && long.Parse(whole.Groups[1].Value) == have) return;
                        File.Delete(path);
                        throw new Exception("its download did not fit what was held, started again");
                    }
                    if (IsMissing(error, at)) throw new Final("its download is gone: " + at);
                    throw;
                }
            }
        }
    }

    static class GitHub
    {
        static DateTime wait = DateTime.MinValue;

        // "https://github.com/owner/name/...", "github.com/owner/name.git",
        // "git@github.com:owner/name" or "owner/name": "owner/name"; else null.
        public static string ParseRepo(string given)
        {
            string text = (given ?? "").Trim().Trim('"', '\'', '<', '>');
            Match link = Regex.Match(text, @"^(?:git@github\.com:|(?:https?://)?(?:www\.)?github\.com/)([^/?#\s]+)/([^/?#\s]+)", RegexOptions.IgnoreCase);
            string owner, name;
            if (link.Success)
            {
                owner = link.Groups[1].Value;
                name = link.Groups[2].Value;
            }
            else
            {
                Match plain = Regex.Match(text, @"^([^/\s]+)/([^/\s]+?)/?$");
                if (!plain.Success || plain.Groups[1].Value.Contains(".")) return null;
                owner = plain.Groups[1].Value;
                name = plain.Groups[2].Value;
            }
            if (name.EndsWith(".git", StringComparison.OrdinalIgnoreCase)) name = name.Substring(0, name.Length - 4);
            if (!Regex.IsMatch(owner, @"^[A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38}$")) return null;
            if (!Regex.IsMatch(name, @"^[A-Za-z0-9._-]{1,100}$") || name == "." || name == "..") return null;
            return owner + "/" + name;
        }

        static string Limit()
        {
            return "GitHub's limit of 60 checks an hour is used up until " + wait.ToString("HH:mm");
        }

        // Tests: the API's answers made up, and the calls counted.
        public static Func<string, string> FakeApi = null;
        public static int Calls;

        public static string Api(string path)
        {
            if (FakeApi != null) { Calls++; return FakeApi(path); }
            if (Core.Env("FUM_NO_API") == "1") throw new ApiOut("the API is off for this test");
            if (DateTime.Now < wait) throw new ApiOut(Limit());
            Calls++;
            HttpWebRequest request = Net.Make("https://api.github.com/" + path);
            request.Accept = "application/vnd.github+json";
            try
            {
                using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
                using (StreamReader reader = new StreamReader(response.GetResponseStream(), Encoding.UTF8))
                    return reader.ReadToEnd();
            }
            catch (WebException error)
            {
                HttpWebResponse response = error.Response as HttpWebResponse;
                if (response == null) throw new ApiOut("GitHub's API did not answer (" + error.Message + ")");
                using (response)
                {
                    if (response.StatusCode == HttpStatusCode.NotFound) throw new Final("GitHub has no repository by that name");
                    long reset;
                    if (response.Headers["X-RateLimit-Remaining"] == "0" && long.TryParse(response.Headers["X-RateLimit-Reset"], out reset))
                    {
                        wait = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddSeconds(reset).ToLocalTime();
                        throw new ApiOut(Limit());
                    }
                    throw new Exception("GitHub answered " + (int)response.StatusCode + " " + response.StatusDescription);
                }
            }
        }

        // The newest stable release of the addon and its zip for WoW
        // Forever. The API first; with the API out, GitHub's pages (counted
        // in no limit).
        public static Release Latest(TrackedAddon a)
        {
            return Latest(a.Repo, a.Series, a.ZipPattern, a.Betas);
        }

        public static Release Latest(string repo, string series, string zipPattern)
        {
            return Latest(repo, series, zipPattern, false);
        }

        // Betas: the newest release, test versions (pre-releases) too.
        public static Release Latest(string repo, string series, string zipPattern, bool betas)
        {
            try { return ByApi(repo, series, zipPattern, betas); }
            catch (ApiOut why)
            {
                try { return ByWeb(repo, series, zipPattern, betas); }
                catch (Final) { throw; }
                catch (Exception web) { throw new Exception(why.Message + "; the release page did not answer either (" + web.Message + ")"); }
            }
        }

        // Its version tags: "v0.3.1", "1.2"; not "lib-v1.2" (another thing
        // the same repository ships).
        static bool PlainTag(string tag)
        {
            return Regex.IsMatch(tag ?? "", @"^[vV]?\d");
        }

        public const string NoStable = "it has no stable release of this addon";

        // A page of a repository's releases, newest first. A page read in
        // the last two minutes is not asked again: Spoken and its four voice
        // packs share one repository, and one call.
        static readonly Dictionary<string, KeyValuePair<DateTime, object[]>> pages = new Dictionary<string, KeyValuePair<DateTime, object[]>>(StringComparer.OrdinalIgnoreCase);

        static object[] Releases(string repo, int per, int page)
        {
            string path = "repos/" + repo + "/releases?per_page=" + per + (page > 1 ? "&page=" + page : "");
            KeyValuePair<DateTime, object[]> held;
            lock (pages)
                if (pages.TryGetValue(path, out held) && DateTime.Now - held.Key < TimeSpan.FromMinutes(2)) return held.Value;
            object[] list = Json.Parse(Api(path)) as object[];
            if (list == null) throw new Exception("GitHub's answer could not be read");
            lock (pages) pages[path] = new KeyValuePair<DateTime, object[]>(DateTime.Now, list);
            return list;
        }

        public static void Forget() { lock (pages) pages.Clear(); }

        // A repository that ships several things may have the newest release
        // of a series far down its list (Spoken's has 140 releases of a dozen
        // things): pages of 100 are read until one of the series turns up,
        // three at most.
        static Release ByApi(string repo, string series, string zipPattern, bool betas)
        {
            int per = series == null ? 30 : 100, most = series == null ? 1 : 3, seen = 0;
            List<Dictionary<string, object>> stable = new List<Dictionary<string, object>>();
            for (int page = 1; page <= most && stable.Count == 0; page++)
            {
                object[] list = Releases(repo, per, page);
                seen += list.Length;
                foreach (object each in list)
                {
                    Dictionary<string, object> release = each as Dictionary<string, object>;
                    if (release == null || Json.Bool(release, "draft") || (!betas && Json.Bool(release, "prerelease"))) continue;
                    if (series != null && !Regex.IsMatch(Json.Str(release, "tag_name") ?? "", series)) continue;
                    stable.Add(release);
                }
                if (list.Length < per) break;
            }
            if (stable.Count == 0) throw new Final(seen == 0 ? "it has no release yet" : NoStable);
            Dictionary<string, object> pick = series == null ? (stable.FirstOrDefault(r => PlainTag(Json.Str(r, "tag_name"))) ?? stable[0]) : stable[0];
            Release found = new Release();
            found.Repo = repo;
            found.Tag = Json.Str(pick, "tag_name");
            found.Test = Json.Bool(pick, "prerelease");
            found.Published = Json.Str(pick, "published_at");
            found.Notes = Json.Str(pick, "body");
            found.PageUrl = Json.Str(pick, "html_url");
            List<Asset> assets = new List<Asset>();
            foreach (object a in Json.Arr(pick, "assets"))
            {
                Dictionary<string, object> asset = a as Dictionary<string, object>;
                if (asset == null) continue;
                assets.Add(new Asset
                {
                    Name = Json.Str(asset, "name") ?? "",
                    Url = Json.Str(asset, "browser_download_url"),
                    Size = Json.Long(asset, "size"),
                    Sha256 = Digest(Json.Str(asset, "digest"))
                });
            }
            PickZip(found, assets, zipPattern, RepoName(repo));
            Sums(found, assets);
            return found;
        }

        static string RepoName(string repo)
        {
            return repo.Substring(repo.IndexOf('/') + 1);
        }

        // Repositories GitHub's search finds for these words (forks left
        // out): one call, counted in the search's own limit of 10 a minute.
        public static List<string> Search(string words)
        {
            object top = Json.Parse(Api("search/repositories?q=" + Uri.EscapeDataString(words) + "&per_page=30"));
            List<string> found = new List<string>();
            foreach (object each in Json.Arr(top as Dictionary<string, object>, "items"))
            {
                Dictionary<string, object> item = each as Dictionary<string, object>;
                if (item == null || Json.Bool(item, "fork") || Json.Bool(item, "archived")) continue;
                string repo = ParseRepo(Json.Str(item, "full_name"));
                if (repo != null) found.Add(repo);
            }
            return found;
        }

        // "sha256:ab12..." as GitHub gives it: "ab12..."; else null.
        public static string Digest(string digest)
        {
            if (digest == null) return null;
            Match sha = Regex.Match(digest, "^sha256:([0-9a-fA-F]{64})$");
            return sha.Success ? sha.Groups[1].Value.ToLowerInvariant() : null;
        }

        public static bool Like(string name, string pattern)
        {
            return Regex.IsMatch(name, "^" + Regex.Escape(pattern).Replace(@"\*", ".*").Replace(@"\?", ".") + "$", RegexOptions.IgnoreCase);
        }

        // Which zip is the one for WoW Forever: the one its known name says;
        // else the release.json addon packagers put beside their zips (flavor
        // "forever", or an Interface of 1.6x); else the release's only zip,
        // the one named for Forever, the one named for the repository, or
        // the one not named for another game.
        public static void PickZip(Release release, List<Asset> assets, string zipPattern, string repoName)
        {
            List<Asset> zips = assets.FindAll(a => a.Name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase));
            if (zipPattern != null)
            {
                List<Asset> named = zips.FindAll(a => Like(a.Name, zipPattern));
                if (named.Count != 1) throw new Final("its release " + release.Tag + " has " + (named.Count == 0 ? "no zip" : "several zips") + " named like " + zipPattern);
                Take(release, named[0], "its zip by name");
                return;
            }
            Asset meta = assets.Find(a => string.Equals(a.Name, "release.json", StringComparison.OrdinalIgnoreCase));
            if (meta != null && meta.Url != null)
            {
                string chosen = ForeverIn(Net.Text(meta.Url));
                if (chosen == null) throw new Final("its release " + release.Tag + " has no build for WoW Forever (its release.json lists none)");
                Asset zip = assets.Find(a => string.Equals(a.Name, chosen, StringComparison.OrdinalIgnoreCase));
                if (zip == null) throw new Final("its release.json names " + chosen + ", which is not in release " + release.Tag);
                Take(release, zip, "the release.json picks it for WoW Forever");
                return;
            }
            string chosenName = ZipByName(zips.ConvertAll(a => a.Name), repoName);
            Asset one = chosenName == null ? null : zips.Find(a => a.Name == chosenName);
            if (one == null)
                throw new Final(zips.Count == 0 ? "its release " + release.Tag + " has no zip"
                    : "its release " + release.Tag + " has several zips (" + string.Join(", ", zips.ConvertAll(a => a.Name).ToArray()) + ") and nothing saying which is for WoW Forever");
            Take(release, one, zips.Count == 1 ? "the release's only zip" : "picked by its name");
        }

        // Of a release's zip names, the one for WoW Forever without a
        // release.json; null when that cannot be told.
        public static string ZipByName(List<string> zips, string repoName)
        {
            if (zips.Count == 1) return zips[0];
            string forever = zips.Find(n => Regex.IsMatch(n, "forever|camelot", RegexOptions.IgnoreCase));
            if (forever != null) return forever;
            List<string> own = zips.FindAll(n => Regex.IsMatch(n, "^" + Regex.Escape(repoName) + @"[-_ ]?[vV]?\d", RegexOptions.IgnoreCase));
            if (own.Count == 1) return own[0];
            List<string> plain = zips.FindAll(n => !Regex.IsMatch(n, @"(^|[-_. ])(classic|vanilla|era|sod|bcc|tbc|wrath|wotlk|cata|mists|mop|nolib)([-_. ]|$)", RegexOptions.IgnoreCase));
            return plain.Count == 1 ? plain[0] : null;
        }

        static void Take(Release release, Asset zip, string why)
        {
            release.ZipName = zip.Name;
            release.ZipUrl = zip.Url;
            release.Size = zip.Size;
            release.Sha256 = zip.Sha256;
            release.PickedBy = why;
        }

        static readonly string[] SumsNames = { "SHA256SUMS", "SHA256SUMS.txt", "sha256sums.txt", "checksums.txt", "checksums.sha256" };

        // The author's own list of sha256s beside the zips, when there is
        // one: it must agree with GitHub's.
        static void Sums(Release release, List<Asset> assets)
        {
            Asset sums = assets.Find(a => SumsNames.Any(n => string.Equals(n, a.Name, StringComparison.OrdinalIgnoreCase)));
            if (sums == null || sums.Url == null) return;
            Dictionary<string, string> listed = ParseSums(Net.Text(sums.Url));
            string sha;
            if (!listed.TryGetValue(release.ZipName, out sha)) return;
            if (release.Sha256 != null && release.Sha256 != sha)
                throw new Final("GitHub's sha256 for " + release.ZipName + " and the release's " + sums.Name + " disagree");
            release.Sha256 = sha;
            release.PickedBy += ", checked against its " + sums.Name;
        }

        // "<sha256>  <file>" lines (a "*" before the file for binary mode).
        public static Dictionary<string, string> ParseSums(string text)
        {
            Dictionary<string, string> listed = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (string line in text.Split('\n'))
            {
                Match m = Regex.Match(line.Trim(), @"^([0-9a-fA-F]{64})\s+\*?(.+)$");
                if (m.Success) listed[m.Groups[2].Value.Trim()] = m.Groups[1].Value.ToLowerInvariant();
            }
            return listed;
        }

        // The zip release.json lists for WoW Forever, the full one before a
        // "nolib" one; null when it lists none.
        public static string ForeverIn(string releaseJson)
        {
            Dictionary<string, object> top = Json.Parse(releaseJson) as Dictionary<string, object>;
            string best = null;
            foreach (object each in Json.Arr(top, "releases"))
            {
                Dictionary<string, object> entry = each as Dictionary<string, object>;
                string file = Json.Str(entry, "filename");
                if (file == null || file.IndexOfAny(new[] { '/', '\\' }) >= 0) continue;
                bool forever = false;
                foreach (object m in Json.Arr(entry, "metadata"))
                {
                    Dictionary<string, object> meta = m as Dictionary<string, object>;
                    string flavor = (Json.Str(meta, "flavor") ?? "").ToLowerInvariant();
                    long iface = Json.Long(meta, "interface");
                    if (flavor == "forever" || flavor == "camelot" || (iface >= 16000 && iface < 17000)) forever = true;
                }
                if (!forever) continue;
                if (!Json.Bool(entry, "nolib")) return file;
                if (best == null) best = file;
            }
            return best;
        }

        // The web's way: releases/latest lands on the newest stable tag; the
        // release's release.json, or its SHA256SUMS, names the zip. No size
        // this way, and a sha256 only from SHA256SUMS.
        static Release ByWeb(string repo, string series, string zipPattern, bool betas)
        {
            string landed = Net.Landing("https://github.com/" + repo + "/releases/latest");
            Match tag = Regex.Match(landed, @"/releases/tag/([^?#]+)$");
            if (!tag.Success && series == null) throw new Final("it has no stable release");
            string tagName = tag.Success ? Uri.UnescapeDataString(tag.Groups[1].Value) : "";
            // Another of the repository's things is its newest: the series'
            // newest tag from git's own list instead.
            if (series != null && !Regex.IsMatch(tagName, series)) return BySeriesWeb(repo, series, zipPattern, betas);
            if (series == null && !PlainTag(tagName))
                throw new Exception("its newest release on GitHub's page (" + tagName + ") is another of the repository's things; checked again later");
            string downloads = "https://github.com/" + repo + "/releases/download/" + TagPath(tagName) + "/";
            Release release = new Release();
            release.Repo = repo;
            release.Tag = tagName;
            release.PageUrl = landed;
            Dictionary<string, string> sums = null;
            foreach (string name in SumsNames)
            {
                try { sums = ParseSums(Net.Text(downloads + name)); break; }
                catch (Final) { }
            }
            string chosen = null;
            if (zipPattern != null)
            {
                if (sums != null) chosen = sums.Keys.FirstOrDefault(n => Like(n, zipPattern));
                release.PickedBy = "its zip by name (read from GitHub's page)";
            }
            else
            {
                try
                {
                    chosen = ForeverIn(Net.Text(downloads + "release.json"));
                    if (chosen == null) throw new Final("its release has no build for WoW Forever (its release.json lists none)");
                    release.PickedBy = "the release.json picks it for WoW Forever (read from GitHub's page)";
                }
                catch (Final why)
                {
                    if (!why.Message.StartsWith("not found")) throw;
                    if (sums != null) chosen = ZipByName(sums.Keys.Where(n => n.EndsWith(".zip", StringComparison.OrdinalIgnoreCase)).ToList(), RepoName(repo));
                    release.PickedBy = "picked by its name (read from GitHub's page)";
                }
            }
            if (chosen == null)
            {
                // No SHA256SUMS or release.json to name it (Spoken's, OpenMap's): the release's own list of files.
                List<Asset> listed = WebAssets(repo, tagName);
                if (listed == null) throw new Exception("without GitHub's API its zip cannot be told; checked again later");
                PickZip(release, listed, zipPattern, RepoName(repo));
                release.PickedBy += " (read from GitHub's page)";
                Sums(release, listed);
                if (release.Sha256 != null && !release.PickedBy.Contains("checked against")) release.PickedBy += ", checked against GitHub's sha256";
                return release;
            }
            if (chosen == null) throw new Exception("without GitHub's API its zip cannot be told; checked again later");
            release.ZipName = chosen;
            release.ZipUrl = downloads + Uri.EscapeDataString(chosen);
            string sha;
            if (sums != null && sums.TryGetValue(chosen, out sha)) { release.Sha256 = sha; release.PickedBy += ", checked against its SHA256SUMS"; }
            else
            {
                // GitHub's own sha256, from the release's page.
                List<Asset> listed = null;
                try { listed = WebAssets(repo, tagName); } catch (Exception) { }
                Asset same = listed == null ? null : listed.Find(x => x.Name == chosen && x.Sha256 != null);
                if (same != null) { release.Sha256 = same.Sha256; release.PickedBy += ", checked against GitHub's sha256"; }
            }
            return release;
        }

        // A tag in an address: each part escaped, "quests-audio%2Fv2.5.0"
        // as GitHub writes it.
        static string TagPath(string tag)
        {
            return Uri.EscapeDataString(tag);
        }

        // Without the API, the newest release of a series: the repository's
        // tags from git's own list (github.com/<repo>.git/info/refs, counted
        // in no limit), the newest of the series by its version, then the
        // release's files and sha256s from its page. A tag with no release,
        // or a test version, gives way to the one before (three at most).
        static Release BySeriesWeb(string repo, string series, string zipPattern, bool betas)
        {
            string refs;
            HttpWebRequest request = Net.Make("https://github.com/" + repo + ".git/info/refs?service=git-upload-pack");
            try
            {
                using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
                using (Stream input = response.GetResponseStream())
                    refs = Encoding.UTF8.GetString(Net.ReadCapped(input, 8 * 1024 * 1024));
            }
            catch (WebException error)
            {
                if (Net.IsMissing(error, null)) throw new Final("GitHub has no repository by that name");
                throw;
            }
            List<string> tags = NewestFirst(TagsIn(refs), series);
            if (tags.Count == 0) throw new Final(NoStable);
            foreach (string tagName in tags.Take(3))
            {
                List<Asset> assets = WebAssets(repo, tagName);
                if (assets == null) continue;
                if (!betas && TestVersion(repo, tagName)) continue;
                Release release = new Release { Repo = repo, Tag = tagName, PageUrl = "https://github.com/" + repo + "/releases/tag/" + TagPath(tagName) };
                PickZip(release, assets, zipPattern, RepoName(repo));
                release.PickedBy += " (read from GitHub's pages)";
                Sums(release, assets);
                if (release.Sha256 != null && !release.PickedBy.Contains("checked against")) release.PickedBy += ", checked against GitHub's sha256";
                return release;
            }
            throw new Exception("without GitHub's API its newest release (" + tags[0] + ") cannot be told; checked again later");
        }

        // The tags in git's list of refs ("<sha> refs/tags/<name>" lines).
        public static List<string> TagsIn(string refs)
        {
            List<string> tags = new List<string>();
            foreach (Match m in Regex.Matches(refs, @"refs/tags/([^\s\^\x00]+)"))
                if (!tags.Contains(m.Groups[1].Value)) tags.Add(m.Groups[1].Value);
            return tags;
        }

        // The tags of a series, the newest version first ("quests-audio/v2.10.0"
        // before "quests-audio/v2.9.1": the version is what follows the last /).
        public static List<string> NewestFirst(List<string> tags, string series)
        {
            List<string> mine = tags.Where(t => Regex.IsMatch(t, series)).ToList();
            mine.Sort((a, b) => Core.CompareVersions(b.Substring(b.LastIndexOf('/') + 1), a.Substring(a.LastIndexOf('/') + 1)));
            return mine;
        }

        // A release's files from its page (releases/expanded_assets/<tag>):
        // each one's name, address and GitHub's sha256. Null when the tag has
        // no release.
        static List<Asset> WebAssets(string repo, string tag)
        {
            string page;
            try { page = Net.Text("https://github.com/" + repo + "/releases/expanded_assets/" + TagPath(tag)); }
            catch (Final) { return null; }
            List<Asset> assets = ParseAssets(page, repo);
            return assets.Count > 0 ? assets : null;
        }

        public static List<Asset> ParseAssets(string page, string repo)
        {
            List<Asset> assets = new List<Asset>();
            string own = "/" + repo + "/releases/download/";
            foreach (string item in page.Split(new[] { "<li" }, StringSplitOptions.None))
            {
                Match link = Regex.Match(item, "href=\"(" + Regex.Escape(own) + "[^\"/]+/([^\"/]+))\"", RegexOptions.IgnoreCase);
                if (!link.Success) continue;
                string name = Uri.UnescapeDataString(link.Groups[2].Value);
                if (assets.Exists(a => a.Name == name)) continue;
                Match sha = Regex.Match(item, @"sha256:([0-9a-f]{64})");
                assets.Add(new Asset { Name = name, Url = "https://github.com" + System.Net.WebUtility.HtmlDecode(link.Groups[1].Value), Sha256 = sha.Success ? sha.Groups[1].Value : null });
            }
            return assets;
        }

        // A release page marked as a test version (pre-release).
        static bool TestVersion(string repo, string tag)
        {
            try { return Regex.IsMatch(Net.Text("https://github.com/" + repo + "/releases/tag/" + TagPath(tag)), @">\s*Pre-release\s*<"); }
            catch (Final) { return false; }
        }
    }

    // Ed25519 signatures checked (RFC 8032, 5.1.7), for polestar.guide's
    // signed guide list: .NET Framework has no ed25519 of its own. Plain
    // arithmetic after the RFC's reference code; it only ever checks public
    // data, so it needs no guard against timing.
    static class Ed25519
    {
        static readonly BigInteger P = BigInteger.Pow(2, 255) - 19;
        static readonly BigInteger L = BigInteger.Pow(2, 252) + BigInteger.Parse("27742317777372353535851937790883648493");
        static readonly BigInteger D = Mod(-121665 * Inv(121666));
        static readonly BigInteger SqrtM1 = BigInteger.ModPow(2, (P - 1) / 4, P);
        static readonly BigInteger[] G = BasePoint();

        static BigInteger Mod(BigInteger a)
        {
            BigInteger r = a % P;
            return r.Sign < 0 ? r + P : r;
        }

        static BigInteger Inv(BigInteger a)
        {
            return BigInteger.ModPow(Mod(a), P - 2, P);
        }

        static BigInteger[] BasePoint()
        {
            BigInteger y = Mod(4 * Inv(5));
            BigInteger x = RecoverX(y, 0);
            return new[] { x, y, BigInteger.One, Mod(x * y) };
        }

        static BigInteger[] Add(BigInteger[] p, BigInteger[] q)
        {
            BigInteger a = Mod((p[1] - p[0]) * (q[1] - q[0]));
            BigInteger b = Mod((p[1] + p[0]) * (q[1] + q[0]));
            BigInteger c = Mod(2 * p[3] * q[3] * D);
            BigInteger d = Mod(2 * p[2] * q[2]);
            BigInteger e = b - a, f = d - c, g = d + c, h = b + a;
            return new[] { Mod(e * f), Mod(g * h), Mod(f * g), Mod(e * h) };
        }

        static BigInteger[] Times(BigInteger s, BigInteger[] p)
        {
            BigInteger[] q = { BigInteger.Zero, BigInteger.One, BigInteger.One, BigInteger.Zero };
            while (s.Sign > 0)
            {
                if (!s.IsEven) q = Add(q, p);
                p = Add(p, p);
                s >>= 1;
            }
            return q;
        }

        static bool Same(BigInteger[] p, BigInteger[] q)
        {
            return Mod(p[0] * q[2] - q[0] * p[2]).IsZero && Mod(p[1] * q[2] - q[1] * p[2]).IsZero;
        }

        // x from y and its sign bit; -1 when there is none.
        static BigInteger RecoverX(BigInteger y, int sign)
        {
            if (y >= P) return BigInteger.MinusOne;
            BigInteger x2 = Mod((y * y - 1) * Inv(D * y * y + 1));
            if (x2.IsZero) return sign != 0 ? BigInteger.MinusOne : BigInteger.Zero;
            BigInteger x = BigInteger.ModPow(x2, (P + 3) / 8, P);
            if (!Mod(x * x - x2).IsZero) x = Mod(x * SqrtM1);
            if (!Mod(x * x - x2).IsZero) return BigInteger.MinusOne;
            if ((int)(x & 1) != sign) x = P - x;
            return x;
        }

        static BigInteger[] Decompress(byte[] s)
        {
            BigInteger y = Number(s);
            int sign = (int)(y >> 255);
            y &= (BigInteger.One << 255) - 1;
            BigInteger x = RecoverX(y, sign);
            if (x.Sign < 0) return null;
            return new[] { x, y, BigInteger.One, Mod(x * y) };
        }

        static BigInteger Number(byte[] littleEndian)
        {
            byte[] bytes = new byte[littleEndian.Length + 1];
            Array.Copy(littleEndian, bytes, littleEndian.Length);
            return new BigInteger(bytes);
        }

        public static bool Verify(byte[] key, byte[] message, byte[] signature)
        {
            if (key == null || key.Length != 32 || signature == null || signature.Length != 64 || message == null) return false;
            BigInteger[] a = Decompress(key);
            if (a == null) return false;
            byte[] rBytes = new byte[32], sBytes = new byte[32];
            Array.Copy(signature, 0, rBytes, 0, 32);
            Array.Copy(signature, 32, sBytes, 0, 32);
            BigInteger[] r = Decompress(rBytes);
            if (r == null) return false;
            BigInteger s = Number(sBytes);
            if (s >= L) return false;
            byte[] all = new byte[64 + message.Length];
            Array.Copy(rBytes, 0, all, 0, 32);
            Array.Copy(key, 0, all, 32, 32);
            Array.Copy(message, 0, all, 64, message.Length);
            byte[] hash;
            using (SHA512 sha = SHA512.Create()) hash = sha.ComputeHash(all);
            BigInteger h = Number(hash) % L;
            return Same(Times(s, G), Add(r, Times(h, a)));
        }
    }

    // A guide on polestar.guide's list.
    class PackEntry
    {
        public string Id, Uid, PublisherId, PublisherHandle, Title, Author, Version, Url, Sha256, MinPolestar, Homepage, Changelog, Published;
        public string[] Folders;
        public long Size;
        public int Toc;
        public bool Reviewed;

        public Release AsRelease()
        {
            return new Release
            {
                Repo = "pack:" + Id, Tag = Version, Published = Published, Notes = Changelog, PageUrl = Homepage,
                ZipName = Id + "-" + Version + ".zip", ZipUrl = Url, Sha256 = Sha256, Size = Size,
                PickedBy = "from polestar.guide's signed guide list", Origin = Packs.Base, Cap = Packs.MaxZip
            };
        }
    }

    class PackRevoke
    {
        public string Id, Uid, Reason;
        public string[] Versions;        // null: every version
        public bool Remove;
    }

    class PackIndex
    {
        public DateTime Generated, Expires;
        public List<PackEntry> Packs = new List<PackEntry>();
        public List<PackRevoke> Revoked = new List<PackRevoke>();

        // The pull that covers a guide at a version; "remove" before
        // "disable" when several do. Both send its folders to the Recycle Bin here.
        public PackRevoke Revocation(string id, string uid, string version)
        {
            PackRevoke found = null;
            foreach (PackRevoke r in Revoked)
            {
                if (r.Id != id || (uid != null && r.Uid != uid)) continue;
                if (r.Versions != null && (version == null || Array.IndexOf(r.Versions, version) < 0)) continue;
                if (found == null || (r.Remove && !found.Remove)) found = r;
            }
            return found;
        }
    }

    // Polestar's community guides, from polestar.guide: its guide list,
    // trusted only with its ed25519 signature from one of Polestar's own
    // keys, and each guide's zip checked to hold only what Polestar's guide
    // compiler makes. The same rules as Polestar's own client (its
    // apps/client/src-tauri/src/packs.rs), written again here.
    static class Packs
    {
        public const string Base = "https://polestar.guide";
        const string IndexPath = "/api/v1/packs/index.json";
        public const long MaxZip = 20 * 1024 * 1024;
        const long MaxUnpacked = 100 * 1024 * 1024;
        const int MaxEntries = 10000;
        const long MaxIndex = 8 * 1024 * 1024;
        const string Prefix = "PolestarPack_";
        public static readonly TimeSpan AutoHold = TimeSpan.FromDays(1);

        // Polestar's public signing keys: the live one and the one held for rotation.
        static readonly Dictionary<string, byte[]> Keys = new Dictionary<string, byte[]>
        {
            { "polestar-1", Hex("af69a8b768efea39d9a96603b6fd98731377c123f6754a1ecd7dc9fdb369abe8") },
            { "polestar-2", Hex("f3f4c0f9d93abd25edeba16e83fc05e3a70c995629fa7fa28ef0b2b8409fbb88") },
        };

        static readonly string[] TocKeys = { "Interface", "Title", "Notes", "Author", "Version", "Category", "Group", "Dependencies", "LoadOnDemand",
            "X-Polestar-Pack", "X-Polestar-Format", "X-Polestar-Needs", "X-Polestar-Texts", "X-Polestar-Locale", "X-License", "X-Website" };
        static readonly string[] MainFiles = { "Pack.lua", "MapFrames.lua", "Guides.lua" };
        static readonly string[] TextsFiles = { "Texts.lua" };
        static readonly string[] FileKinds = { ".toc", ".lua", ".tga", ".blp" };

        static byte[] Hex(string hex)
        {
            byte[] bytes = new byte[hex.Length / 2];
            for (int i = 0; i < bytes.Length; i++) bytes[i] = Convert.ToByte(hex.Substring(i * 2, 2), 16);
            return bytes;
        }

        public static bool ValidId(string id)
        {
            return id != null && Regex.IsMatch(id, "^[a-z0-9][a-z0-9-]{1,31}$");
        }

        public static string MainFolder(string id) { return Prefix + id; }

        // A guide's folder: its id, and its locale for a texts folder
        // ("PolestarPack_lightforge_deDE"); null when it is not one.
        static string[] ParseFolder(string name)
        {
            if (name == null || !name.StartsWith(Prefix, StringComparison.Ordinal)) return null;
            string rest = name.Substring(Prefix.Length);
            int cut = rest.IndexOf('_');
            string id = cut < 0 ? rest : rest.Substring(0, cut), locale = cut < 0 ? null : rest.Substring(cut + 1);
            if (!ValidId(id) || (locale != null && !Regex.IsMatch(locale, "^[a-z]{2}[A-Z]{2}$"))) return null;
            return new[] { id, locale };
        }

        static bool Token(string s) { return s != null && s.Length >= 1 && s.Length <= 64 && s.All(c => c > ' ' && c < 127); }

        static bool Plain(string s, int max) { return s != null && s.Trim() != "" && s.Length <= max && !s.Any(char.IsControl); }

        public static DateTime? Time(string iso)
        {
            DateTime when;
            if (iso == null || !iso.EndsWith("Z")) return null;
            return DateTime.TryParse(iso, CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out when) ? when : (DateTime?)null;
        }

        static string Folder() { string dir = Path.Combine(Core.Home(), "packs"); Directory.CreateDirectory(dir); return dir; }

        // The guide list: fetched (with the ETag of the one held), its
        // signature fetched and checked, kept for offline. Throws, saying why.
        public static PackIndex Fetch()
        {
            string dir = Folder(), bodyPath = Path.Combine(dir, "index.json"), sigPath = Path.Combine(dir, "index.json.sig");
            string etag = Core.Setting("packsEtag", "");
            long lastMs;
            long.TryParse(Core.Setting("packsGenerated", "0"), out lastMs);
            DateTime? last = lastMs > 0 ? new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddMilliseconds(lastMs) : (DateTime?)null;
            bool held = File.Exists(bodyPath) && File.Exists(sigPath);
            HttpWebRequest request = Net.Make(Base + IndexPath);
            request.AllowAutoRedirect = false;
            if (held && etag != "") request.Headers["If-None-Match"] = etag;
            byte[] body;
            string tagNow;
            try
            {
                using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
                {
                    // Without redirects, a 304 comes back as an answer, not an error.
                    if (response.StatusCode == HttpStatusCode.NotModified && held)
                        return Verify(File.ReadAllBytes(bodyPath), File.ReadAllBytes(sigPath), null, DateTime.UtcNow);
                    if ((int)response.StatusCode != 200) throw new Exception("polestar.guide answered " + (int)response.StatusCode + " for its guide list");
                    tagNow = response.Headers["ETag"];
                    using (Stream input = response.GetResponseStream()) body = Net.ReadCapped(input, MaxIndex);
                }
            }
            catch (WebException error)
            {
                HttpWebResponse response = error.Response as HttpWebResponse;
                if (response != null)
                    using (response)
                        if (response.StatusCode == HttpStatusCode.NotModified && held)
                            return Verify(File.ReadAllBytes(bodyPath), File.ReadAllBytes(sigPath), null, DateTime.UtcNow);
                throw new Exception("polestar.guide did not give its guide list (" + error.Message + ")");
            }
            string snapshot = Snapshot(tagNow);
            HttpWebRequest sigRequest = Net.Make(Base + IndexPath + ".sig" + (snapshot != null ? "?for=" + snapshot : ""));
            sigRequest.AllowAutoRedirect = false;
            byte[] sig;
            try
            {
                using (HttpWebResponse response = (HttpWebResponse)sigRequest.GetResponse())
                using (Stream input = response.GetResponseStream()) sig = Net.ReadCapped(input, 64 * 1024);
            }
            catch (WebException error)
            {
                throw new Exception("polestar.guide has no signature for its guide list yet (" + error.Message + ")");
            }
            PackIndex index = Verify(body, sig, last, DateTime.UtcNow);
            Core.WriteAll(bodyPath, body);
            Core.WriteAll(sigPath, sig);
            Core.SetSetting("packsEtag", tagNow ?? "");
            Core.SetSetting("packsGenerated", ((long)(index.Generated - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalMilliseconds).ToString(CultureInfo.InvariantCulture));
            return index;
        }

        // The list kept from last time, while it is still good; else null.
        public static PackIndex Held()
        {
            try
            {
                string dir = Folder(), bodyPath = Path.Combine(dir, "index.json"), sigPath = Path.Combine(dir, "index.json.sig");
                if (!File.Exists(bodyPath) || !File.Exists(sigPath)) return null;
                return Verify(File.ReadAllBytes(bodyPath), File.ReadAllBytes(sigPath), null, DateTime.UtcNow);
            }
            catch (Exception why)
            {
                Core.Log("guide list kept: " + why.Message);
                return null;
            }
        }

        // "6-1793119304877" (an ETag): "6", the signature to ask for.
        public static string Snapshot(string etag)
        {
            if (etag == null) return null;
            string tag = etag.Trim();
            if (tag.StartsWith("W/")) tag = tag.Substring(2);
            tag = tag.Trim('"');
            string id = tag.Split('-')[0];
            return id != "" && id.All(char.IsDigit) ? id : null;
        }

        // The signature (a pinned key, the sha256 of the exact bytes, ed25519),
        // then the list it signs: schema 1, a week to live and not past it,
        // never older than the last one taken. Entries that break the rules
        // are left out; the rest stands.
        public static PackIndex Verify(byte[] bytes, byte[] sigBytes, DateTime? last, DateTime now)
        {
            Dictionary<string, object> sig = Json.Parse(Encoding.UTF8.GetString(sigBytes)) as Dictionary<string, object>;
            if (sig == null) throw new Exception("the guide list's signature is unreadable");
            if (Json.Str(sig, "alg") != "ed25519") throw new Exception("the guide list is signed with " + Json.Str(sig, "alg") + ", which is not taken");
            byte[] key;
            if (Json.Str(sig, "keyId") == null || !Keys.TryGetValue(Json.Str(sig, "keyId"), out key))
                throw new Exception("the guide list is signed with a key Polestar does not have (" + Json.Str(sig, "keyId") + ")");
            if (!string.Equals(Core.Sha256Of(bytes), (Json.Str(sig, "sha256") ?? "").Trim(), StringComparison.OrdinalIgnoreCase))
                throw new Exception("the guide list does not match its signature (another copy was signed)");
            byte[] signature;
            try { signature = Convert.FromBase64String((Json.Str(sig, "sig") ?? "").Trim()); }
            catch { throw new Exception("the guide list's signature is unreadable"); }
            if (!Ed25519.Verify(key, bytes, signature)) throw new Exception("the guide list's signature is not valid");

            Dictionary<string, object> raw = Json.Parse(Encoding.UTF8.GetString(bytes)) as Dictionary<string, object>;
            if (raw == null) throw new Exception("the guide list is unreadable");
            if (Json.Long(raw, "schema") != 1) throw new Exception("the guide list is in a newer format (" + Json.Long(raw, "schema") + "): update ForeverUI Manager");
            DateTime? generated = Time(Json.Str(raw, "generated")), expires = Time(Json.Str(raw, "expires"));
            if (generated == null || expires == null) throw new Exception("the guide list has no valid dates");
            if (expires <= generated || expires.Value - generated.Value > TimeSpan.FromDays(7)) throw new Exception("the guide list's expiry is not within a week of its date");
            if (now >= expires.Value) throw new Exception("the guide list has expired: polestar.guide has not renewed it yet");
            if (last != null && generated.Value < last.Value) throw new Exception("the guide list is older than the one taken before");

            PackIndex index = new PackIndex { Generated = generated.Value, Expires = expires.Value };
            foreach (object each in Json.Arr(raw, "packs"))
            {
                string why;
                PackEntry entry = Entry(each as Dictionary<string, object>, out why);
                if (entry != null && !index.Packs.Exists(p => p.Id == entry.Id)) index.Packs.Add(entry);
                else if (why != null) Core.Log("guide left out: " + why);
            }
            foreach (object each in Json.Arr(raw, "revoked"))
            {
                PackRevoke r = Revoke(each as Dictionary<string, object>);
                if (r != null) index.Revoked.Add(r);
            }
            return index;
        }

        static PackEntry Entry(Dictionary<string, object> d, out string why)
        {
            why = null;
            if (d == null) { why = "not an entry"; return null; }
            PackEntry e = new PackEntry();
            e.Id = Json.Str(d, "id");
            if (!ValidId(e.Id)) { why = "bad id " + e.Id; return null; }
            List<string> folders = new List<string>();
            foreach (object f in Json.Arr(d, "addon"))
            {
                string folder = f as string;
                string[] parsed = ParseFolder(folder);
                if (parsed == null || parsed[0] != e.Id || folders.Contains(folder)) { why = e.Id + ": folder " + folder + " is not its own"; return null; }
                folders.Add(folder);
            }
            if (!folders.Contains(MainFolder(e.Id))) { why = e.Id + ": its folders lack " + MainFolder(e.Id); return null; }
            e.Folders = folders.ToArray();
            if (Json.Str(d, "channel") != "stable") { why = e.Id + ": channel " + Json.Str(d, "channel"); return null; }
            e.Title = Json.Str(d, "title");
            e.Author = Json.Str(d, "author");
            e.Version = Json.Str(d, "version");
            if (!Plain(e.Title, 80) || !Plain(e.Author, 64) || !Plain(e.Version, 32)) { why = e.Id + ": title, author or version missing or too long"; return null; }
            Dictionary<string, object> download = Json.Obj(d, "download");
            e.Url = Json.Str(download, "url");
            if (e.Url == null || !e.Url.StartsWith("https://") || !Net.SameOrigin(e.Url, Base)) { why = e.Id + ": its download is not on polestar.guide"; return null; }
            e.Sha256 = (Json.Str(download, "sha256") ?? "").ToLowerInvariant();
            if (!Regex.IsMatch(e.Sha256, "^[0-9a-f]{64}$")) { why = e.Id + ": bad sha256"; return null; }
            e.Size = Json.Long(download, "size");
            if (e.Size <= 0 || e.Size > MaxZip) { why = e.Id + ": size outside 1 byte to 20 MB"; return null; }
            long toc = Json.Long(d, "toc");
            e.Toc = toc > 0 && toc < int.MaxValue ? (int)toc : 0;
            e.Uid = Token(Json.Str(d, "uid")) ? Json.Str(d, "uid") : null;
            Dictionary<string, object> publisher = Json.Obj(d, "publisher");
            if (publisher != null && Token(Json.Str(publisher, "id")))
            {
                e.PublisherId = Json.Str(publisher, "id");
                e.PublisherHandle = Plain(Json.Str(publisher, "handle"), 64) ? Json.Str(publisher, "handle") : null;
            }
            e.Published = Time(Json.Str(d, "published")) != null ? Json.Str(d, "published") : null;
            e.Reviewed = Json.Bool(d, "reviewed");
            string min = Json.Str(d, "minPolestar");
            e.MinPolestar = min != null && min.Length > 0 && min.Length <= 32 ? min : null;
            string home = Json.Str(d, "homepage");
            Uri page;
            e.Homepage = home != null && home.StartsWith("https://") && Uri.TryCreate(home, UriKind.Absolute, out page) ? home : null;
            string changelog = Json.Str(d, "changelog") ?? "";
            e.Changelog = changelog.Length > 20000 ? changelog.Substring(0, 20000) : changelog;
            return e;
        }

        static PackRevoke Revoke(Dictionary<string, object> d)
        {
            if (d == null || !ValidId(Json.Str(d, "id")) || !Token(Json.Str(d, "uid"))) return null;
            PackRevoke r = new PackRevoke { Id = Json.Str(d, "id"), Uid = Json.Str(d, "uid") };
            object versions;
            d.TryGetValue("versions", out versions);
            if ((versions as string) == "*") r.Versions = null;
            else if (versions is object[] && ((object[])versions).All(v => v is string)) r.Versions = ((object[])versions).Cast<string>().ToArray();
            else return null;
            string reason = new string((Json.Str(d, "reason") ?? "").Where(c => !char.IsControl(c)).Take(300).ToArray()).Trim();
            r.Reason = reason != "" ? reason : "The site gave no reason.";
            r.Remove = Json.Str(d, "action") == "remove";
            return r;
        }

        // Which guide a folder in AddOns belongs to, by its .toc
        // (X-Polestar-Pack in the main folder, X-Polestar-Texts in a locale
        // one); null when it carries no id.
        public static string Owner(string folderPath)
        {
            string name = Path.GetFileName(folderPath.TrimEnd('\\'));
            string[] parsed = ParseFolder(name);
            string toc = Path.Combine(folderPath, name + ".toc");
            if (parsed == null || !File.Exists(toc)) return null;
            return OwnerIn(File.ReadAllText(toc), parsed[1] != null);
        }

        static string OwnerIn(string toc, bool locale)
        {
            string field = locale ? "X-Polestar-Texts" : "X-Polestar-Pack";
            foreach (string line in toc.Split('\n'))
            {
                Match m = Regex.Match(line.Trim(), @"^##\s*([^:]+?)\s*:\s*(.*)$");
                if (m.Success && string.Equals(m.Groups[1].Value, field, StringComparison.OrdinalIgnoreCase)) return m.Groups[2].Value.Trim();
            }
            return null;
        }

        // Every folder it would write is free, or already its own.
        public static void CheckOwnership(string addons, PackEntry entry)
        {
            foreach (string folder in entry.Folders)
            {
                string there = Path.Combine(addons, folder);
                if (Directory.Exists(there) && Owner(there) != entry.Id)
                    throw new Final("AddOns\\" + folder + " is in the way: it is not this guide's. Move or rename it first");
            }
        }

        // Its folders in AddOns now, the listed ones and any older locale folder.
        public static List<string> InAddOns(string addons, string id)
        {
            List<string> found = new List<string>();
            if (!Directory.Exists(addons)) return found;
            foreach (string dir in Directory.GetDirectories(addons, Prefix + id + "*"))
            {
                string[] parsed = ParseFolder(Path.GetFileName(dir));
                if (parsed != null && parsed[0] == id && Owner(dir) == id) found.Add(Path.GetFileName(dir));
            }
            return found;
        }

        static readonly Regex Device = new Regex(@"^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\..*)?$", RegexOptions.IgnoreCase);

        static bool SafePart(string part)
        {
            return part != "" && part != "." && part != ".." && part.IndexOfAny(Path.GetInvalidFileNameChars()) < 0
                && !part.EndsWith(".") && !part.EndsWith(" ") && !Device.IsMatch(part);
        }

        static bool AllowedFile(string name)
        {
            string ext = Path.GetExtension(name).ToLowerInvariant(), stem = Path.GetFileNameWithoutExtension(name);
            if (FileKinds.Contains(ext) && stem != "") return true;
            string upper = stem.ToUpperInvariant();
            return (upper.StartsWith("LICENSE") || upper.StartsWith("README")) && (ext == "" || ext == ".txt" || ext == ".md");
        }

        // A guide's zip holds only what Polestar's guide compiler makes: the
        // folders its entry lists, each with its .toc naming the guide and
        // only the lines the compiler writes, the .lua files that .toc loads,
        // .tga and .blp pictures, LICENSE and README texts; within the caps.
        // One thing out of place refuses the whole zip.
        public static void CheckZip(string zip, PackEntry entry)
        {
            using (ZipArchive archive = ZipFile.OpenRead(zip))
            {
                if (archive.Entries.Count > MaxEntries) throw new Final("its zip holds too many files");
                long total = 0;
                List<string> came = new List<string>();
                Dictionary<string, List<string>> luaIn = new Dictionary<string, List<string>>();
                byte[] buffer = new byte[65536];
                foreach (ZipArchiveEntry file in archive.Entries)
                {
                    string name = file.FullName.Replace('\\', '/');
                    bool dir = name.EndsWith("/");
                    string[] parts = name.TrimEnd('/').Split('/');
                    if (name.StartsWith("/") || parts.Any(p => !SafePart(p))) throw new Final("its zip has an unsafe path (" + name + ")");
                    string top = parts[0];
                    if (parts.Length == 1 && !dir) throw new Final("its zip has a file outside its folders (" + name + ")");
                    if (!entry.Folders.Contains(top)) throw new Final("its zip holds a folder that is not this guide's (" + top + ")");
                    if (!came.Contains(top)) came.Add(top);
                    if (dir) continue;
                    string fileName = parts[parts.Length - 1], ext = Path.GetExtension(fileName).ToLowerInvariant();
                    bool topLevel = parts.Length == 2;
                    if (!AllowedFile(fileName) || (ext == ".toc" && (!topLevel || fileName != top + ".toc")) || (ext == ".lua" && !topLevel))
                        throw new Final("its zip holds a file guides may not hold (" + name + ")");
                    if (ext == ".lua")
                    {
                        if (!luaIn.ContainsKey(top)) luaIn[top] = new List<string>();
                        luaIn[top].Add(fileName);
                    }
                    using (Stream input = file.Open())
                    {
                        int read;
                        while ((read = input.Read(buffer, 0, buffer.Length)) > 0)
                        {
                            total += read;
                            if (total > MaxUnpacked) throw new Final("its zip unpacks to more than 100 MB");
                        }
                    }
                }
                foreach (string folder in entry.Folders)
                {
                    if (!came.Contains(folder)) throw new Final("its zip has no " + folder + " folder");
                    bool locale = ParseFolder(folder)[1] != null;
                    ZipArchiveEntry tocEntry = archive.GetEntry(folder + "/" + folder + ".toc");
                    if (tocEntry == null) throw new Final("its zip has no " + folder + ".toc");
                    string toc;
                    using (StreamReader reader = new StreamReader(tocEntry.Open(), Encoding.UTF8)) toc = reader.ReadToEnd();
                    if (OwnerIn(toc, locale) != entry.Id)
                        throw new Final(folder + ".toc does not say it is " + entry.Id + " (## " + (locale ? "X-Polestar-Texts" : "X-Polestar-Pack") + ": " + entry.Id + ")");
                    List<string> listed = CheckToc(toc, locale);
                    List<string> lua;
                    if (luaIn.TryGetValue(folder, out lua))
                        foreach (string file in lua)
                            if (!listed.Any(l => string.Equals(l, file, StringComparison.OrdinalIgnoreCase)))
                                throw new Final("its zip holds " + folder + "/" + file + ", which its .toc does not load");
                }
            }
        }

        // The files a guide's .toc loads, when each of its lines is one the
        // compiler writes: blank, a # comment, a known ## Key, or one of the
        // folder's generated files.
        public static List<string> CheckToc(string text, bool locale)
        {
            string[] files = locale ? TextsFiles : MainFiles;
            List<string> listed = new List<string>();
            foreach (string raw in text.TrimStart('\uFEFF').Split('\n'))
            {
                string line = raw.Trim();
                if (line.StartsWith("##"))
                {
                    int colon = line.IndexOf(':');
                    if (colon < 0) throw new Final("its .toc has a line guides may not have (" + line + ")");
                    string key = line.Substring(2, colon - 2).Trim();
                    bool localized = Regex.IsMatch(key, "^(Title|Notes)-[a-z]{2}[A-Z]{2}$");
                    if (!localized && !TocKeys.Any(k => string.Equals(k, key, StringComparison.OrdinalIgnoreCase)))
                        throw new Final("its .toc has a directive guides may not have (## " + key + ")");
                }
                else if (line == "" || line.StartsWith("#")) continue;
                else
                {
                    string file = files.FirstOrDefault(f => string.Equals(f, line, StringComparison.OrdinalIgnoreCase));
                    if (file == null) throw new Final("its .toc loads a file guides do not have (" + line + ")");
                    listed.Add(file);
                }
            }
            return listed;
        }

        // An installed guide's folder holds only what Polestar's guide
        // compiler makes? Null when it does, else what else it holds (a guide
        // from GitHub may carry code of its own).
        public static string Compiled(string folderPath)
        {
            string name = Path.GetFileName(folderPath.TrimEnd('\\'));
            string tocPath = Path.Combine(folderPath, name + ".toc");
            if (!File.Exists(tocPath)) return "no " + name + ".toc";
            List<string> listed;
            try { listed = CheckToc(File.ReadAllText(tocPath), Regex.IsMatch(name, "_[a-z]{2}[A-Z]{2}$")); }
            catch (Final why) { return why.Message.Replace("its .toc ", "a .toc that "); }
            List<string> own = new List<string>(), other = new List<string>();
            foreach (string file in Directory.GetFiles(folderPath, "*", SearchOption.AllDirectories))
            {
                string fileName = Path.GetFileName(file);
                if (!AllowedFile(fileName)) other.Add(fileName);
                else if (fileName.EndsWith(".lua", StringComparison.OrdinalIgnoreCase) && !listed.Any(l => string.Equals(l, fileName, StringComparison.OrdinalIgnoreCase))) own.Add(fileName);
            }
            if (own.Count == 0 && other.Count == 0) return null;
            List<string> said = new List<string>();
            if (own.Count > 0) said.Add(own.Count + " Lua file(s) of its own (" + string.Join(", ", own.Take(3).ToArray()) + (own.Count > 3 ? "..." : "") + ")");
            if (other.Count > 0) said.Add(other.Count + " other file(s) (" + string.Join(", ", other.Take(3).ToArray()) + (other.Count > 3 ? "..." : "") + ")");
            return string.Join(" and ", said.ToArray());
        }

        // Installs (or updates) a guide: its folders checked as free, the
        // zip from polestar.guide checked by size, sha256 and contents, the
        // folders swapped in like an addon's, its older locale folders out.
        public static Placed Install(string addons, PackEntry entry, string zip, string[] before)
        {
            CheckOwnership(addons, entry);
            Release release = entry.AsRelease();
            Installer.Verify(zip, release);
            CheckZip(zip, entry);
            CheckOwnership(addons, entry);
            List<string> old = InAddOns(addons, entry.Id);
            if (before != null) foreach (string f in before) if (!old.Contains(f) && ParseFolder(f) != null && ParseFolder(f)[0] == entry.Id) old.Add(f);
            return Installer.Put(addons, zip, old.ToArray(), entry.Id + " " + entry.Version);
        }
    }

    class Toc
    {
        public string Title, Version, Interface;
    }

    class Placed
    {
        public string[] Folders;
        public int Skipped;
        public string Left;     // the old copy, when the Recycle Bin refused it
    }

    static class Installer
    {
        // Never put in AddOns: the game runs none of these, and nothing else should.
        static readonly string[] Refused = { ".exe", ".dll", ".bat", ".cmd", ".com", ".ps1", ".psm1", ".vbs", ".vbe", ".js", ".jse",
            ".wsf", ".wsh", ".msi", ".msp", ".scr", ".lnk", ".url", ".hta", ".cpl", ".jar", ".reg", ".sys", ".pif", ".inf", ".ocx",
            ".application", ".appref-ms", ".gadget", ".sh" };

        public static bool SafeFolder(string folder)
        {
            return !string.IsNullOrEmpty(folder) && folder.IndexOfAny(Path.GetInvalidFileNameChars()) < 0 && folder.Trim() == folder
                && !folder.StartsWith(".") && !folder.EndsWith(".") && !folder.StartsWith("Blizzard_", StringComparison.OrdinalIgnoreCase);
        }

        // A .toc names its folder: Folder.toc, or with a game's tag,
        // Folder_Camelot.toc, Folder-Mainline.toc.
        static bool TocOf(string file, string folder)
        {
            if (string.Equals(file, folder, StringComparison.OrdinalIgnoreCase)) return true;
            if (file.Length <= folder.Length + 1 || !file.StartsWith(folder, StringComparison.OrdinalIgnoreCase)) return false;
            char mark = file[folder.Length];
            return (mark == '_' || mark == '-') && Regex.IsMatch(file.Substring(folder.Length + 1), "^[A-Za-z]+$");
        }

        // The addons in a zip, as (its root in the zip, its folder): each
        // folder holding its own .toc, wherever, none inside another; else a
        // .toc at the top of the zip (or of the one folder holding it all, as
        // a repository's own archive has it), named by the .toc.
        public static List<KeyValuePair<string, string>> FoldersIn(IEnumerable<string> entries)
        {
            List<string> names = entries.Select(n => n.Replace('\\', '/')).ToList();
            List<KeyValuePair<string, string>> found = new List<KeyValuePair<string, string>>();
            foreach (string name in names)
            {
                if (name.EndsWith("/") || !name.EndsWith(".toc", StringComparison.OrdinalIgnoreCase)) continue;
                int slash = name.LastIndexOf('/');
                if (slash < 0) continue;
                string prefix = name.Substring(0, slash + 1);
                string file = name.Substring(slash + 1, name.Length - slash - 5);
                string folder = prefix.TrimEnd('/');
                folder = folder.Substring(folder.LastIndexOf('/') + 1);
                if (TocOf(file, folder)) found.Add(new KeyValuePair<string, string>(prefix, folder));
            }
            if (found.Count == 0)
            {
                string top = null;
                foreach (string name in names)
                {
                    int slash = name.IndexOf('/');
                    string first = slash > 0 ? name.Substring(0, slash + 1) : "";
                    if (top == null) top = first;
                    else if (!string.Equals(top, first, StringComparison.OrdinalIgnoreCase)) top = "";
                }
                top = top ?? "";
                List<string> atTop = new List<string>();
                foreach (string name in names)
                {
                    if (!name.EndsWith(".toc", StringComparison.OrdinalIgnoreCase)) continue;
                    int slash = name.LastIndexOf('/');
                    if (!string.Equals(name.Substring(0, slash + 1), top, StringComparison.OrdinalIgnoreCase)) continue;
                    string file = name.Substring(slash + 1, name.Length - slash - 5);
                    atTop.Add(Regex.Replace(file, "[_-][A-Za-z]+$", ""));
                }
                if (atTop.Count > 0)
                {
                    atTop.Sort((a, b) => a.Length != b.Length ? a.Length - b.Length : string.Compare(a, b, StringComparison.OrdinalIgnoreCase));
                    found.Add(new KeyValuePair<string, string>(top, atTop[0]));
                }
            }
            found.Sort((a, b) => a.Key.Length != b.Key.Length ? a.Key.Length - b.Key.Length : string.Compare(a.Key, b.Key, StringComparison.OrdinalIgnoreCase));
            List<KeyValuePair<string, string>> kept = new List<KeyValuePair<string, string>>();
            foreach (KeyValuePair<string, string> each in found)
                if (!kept.Exists(outer => outer.Key.Length > 0 && each.Key.StartsWith(outer.Key, StringComparison.OrdinalIgnoreCase))
                    && !kept.Exists(other => string.Equals(other.Value, each.Value, StringComparison.OrdinalIgnoreCase)))
                    kept.Add(each);
            return kept;
        }

        // A Polestar guide from GitHub: its zip holds PolestarPack_ folders
        // and nothing else, so it cannot put another addon in AddOns.
        public static void OnlyGuides(string zip)
        {
            using (ZipArchive archive = ZipFile.OpenRead(zip))
            {
                List<KeyValuePair<string, string>> folders = FoldersIn(archive.Entries.Select(e => e.FullName));
                if (folders.Count == 0) throw new Final("its zip holds no guide");
                foreach (KeyValuePair<string, string> f in folders)
                    if (!f.Value.StartsWith("PolestarPack_", StringComparison.Ordinal))
                        throw new Final("its zip holds more than a Polestar guide (" + f.Value + ")");
            }
        }

        // Room to work, kept free on each drive besides what is needed.
        const long Spare = 200L * 1048576;

        static string Root(string folder)
        {
            return Path.GetPathRoot(Path.GetFullPath(folder)).ToUpperInvariant();
        }

        // The free room on a folder's drive; FUM_TEST_FREE (tests) says it instead.
        public static long Free(string folder)
        {
            long given;
            if (long.TryParse(Core.Env("FUM_TEST_FREE"), out given)) return given;
            try { return new DriveInfo(Root(folder)).AvailableFreeSpace; }
            catch { return long.MaxValue; }
        }

        static void Need(string folder, long bytes)
        {
            long free = Free(folder);
            if (free < bytes + Spare)
                throw new Exception("there is not room enough on " + Root(folder).TrimEnd('\\') + ": it needs " + Core.Bytes(bytes + Spare) + " free and has " + Core.Bytes(free));
        }

        // Before a download: room for the zip in %TEMP%, and, when AddOns is
        // on the same drive, for what it unpacks to (about the same, for
        // sound, which a zip barely makes smaller). Have: what is held of it.
        public static void RoomToDownload(string temp, string addons, long size, long have)
        {
            if (size <= 0) return;
            long rest = Math.Max(0, size - have);
            if (Root(temp) == Root(addons)) Need(temp, rest + size);
            else { Need(temp, rest); Need(addons, size); }
        }

        // Before unpacking: room beside AddOns for all the zip holds (moved
        // into AddOns after, not copied; the old version goes to the Recycle
        // Bin, on the same drive).
        public static void RoomToUnpack(string addons, string zip)
        {
            long unpacked = 0;
            using (ZipArchive archive = ZipFile.OpenRead(zip))
                foreach (ZipArchiveEntry entry in archive.Entries) unpacked += entry.Length;
            Need(addons, unpacked);
        }

        // Where a GitHub download is held while it comes: one name per file,
        // so one that stopped is taken up again at the next try.
        public static string PartPath(string temp, Release r)
        {
            string id = r.Sha256 != null ? r.Sha256.Substring(0, 16) : "u" + Core.Sha256Of(Encoding.UTF8.GetBytes(r.ZipUrl ?? "")).Substring(0, 15);
            return Path.Combine(temp, id + ".part");
        }

        // Leftovers in the app's temp folder: parts a week old, zips a day old.
        public static void CleanTemp(string temp)
        {
            try
            {
                foreach (string f in Directory.GetFiles(temp))
                {
                    TimeSpan age = DateTime.Now - File.GetLastWriteTime(f);
                    if ((f.EndsWith(".part") && age.TotalDays > 7) || (f.EndsWith(".zip") && age.TotalDays > 1)) File.Delete(f);
                }
            }
            catch { }
        }

        public static void Verify(string zip, Release release)
        {
            long size = new FileInfo(zip).Length;
            if (release.Size > 0 && size != release.Size)
                throw new Exception("the download is " + size + " bytes and its source says " + release.Size);
            if (release.Sha256 != null && !string.Equals(Core.Sha256Of(zip), release.Sha256, StringComparison.OrdinalIgnoreCase))
                throw new Exception("the download does not match the sha256 its source gives");
        }

        static string Stage(string addons)
        {
            string parent = Path.GetDirectoryName(Path.GetFullPath(addons).TrimEnd('\\'));
            return Path.Combine(parent, "_fum-" + Guid.NewGuid().ToString("N").Substring(0, 8));
        }

        static string Plain(string label)
        {
            foreach (char bad in Path.GetInvalidFileNameChars()) label = label.Replace(bad, '-');
            return label.Trim().TrimEnd('.');
        }

        static Exception InUse(string folder, Exception why)
        {
            return new Exception("AddOns\\" + folder + " could not be moved (" + why.Message.TrimEnd('.') + "); is a file of it open?");
        }

        // A zip's addons into AddOns: unpacked beside it first; then each
        // folder it replaces, and each one the last version had and this one
        // has not, moved out; the new ones in; the old ones together to the
        // Recycle Bin. A folder in use puts everything back as it was.
        public static Placed Put(string addons, string zip, string[] before, string label)
        {
            Directory.CreateDirectory(addons);
            string stage = Stage(addons), fresh = Path.Combine(stage, "new"), old = Path.Combine(stage, Plain(label + " (replaced)"));
            Placed placed = new Placed();
            List<string> movedOut = new List<string>(), movedIn = new List<string>();
            try
            {
                List<KeyValuePair<string, string>> folders;
                using (ZipArchive archive = ZipFile.OpenRead(zip))
                {
                    folders = FoldersIn(archive.Entries.Select(e => e.FullName));
                    if (folders.Count == 0) throw new Exception("its zip holds no addon (no folder with its own .toc)");
                    foreach (KeyValuePair<string, string> f in folders)
                        if (!SafeFolder(f.Value)) throw new Exception("its zip has a folder named " + f.Value + ", which is not taken");
                    foreach (KeyValuePair<string, string> f in folders)
                    {
                        string target = Path.GetFullPath(Path.Combine(fresh, f.Value));
                        Directory.CreateDirectory(target);
                        foreach (ZipArchiveEntry entry in archive.Entries)
                        {
                            string name = entry.FullName.Replace('\\', '/');
                            if (entry.Name == "" || !name.StartsWith(f.Key, StringComparison.OrdinalIgnoreCase)) continue;
                            string path;
                            try { path = Path.GetFullPath(Path.Combine(target, name.Substring(f.Key.Length))); }
                            catch { placed.Skipped++; continue; }
                            if (!path.StartsWith(target + "\\", StringComparison.OrdinalIgnoreCase)
                                || Array.IndexOf(Refused, Path.GetExtension(entry.Name).ToLowerInvariant()) >= 0)
                            {
                                placed.Skipped++;
                                continue;
                            }
                            Directory.CreateDirectory(Path.GetDirectoryName(path));
                            entry.ExtractToFile(path, true);
                        }
                    }
                }
                List<string> now = folders.ConvertAll(f => f.Value);
                List<string> outgoing = new List<string>(now);
                if (before != null)
                    foreach (string b in before)
                        if (SafeFolder(b) && !outgoing.Exists(o => string.Equals(o, b, StringComparison.OrdinalIgnoreCase))) outgoing.Add(b);
                Directory.CreateDirectory(old);
                foreach (string f in outgoing)
                {
                    string there = Path.Combine(addons, f);
                    if (!Directory.Exists(there)) continue;
                    try { Directory.Move(there, Path.Combine(old, f)); }
                    catch (Exception why) { throw InUse(f, why); }
                    movedOut.Add(f);
                }
                foreach (string f in now)
                {
                    Directory.Move(Path.Combine(fresh, f), Path.Combine(addons, f));
                    movedIn.Add(f);
                }
                placed.Folders = now.ToArray();
            }
            catch
            {
                foreach (string f in movedIn) try { Directory.Move(Path.Combine(addons, f), Path.Combine(fresh, f)); } catch { }
                foreach (string f in movedOut) try { Directory.Move(Path.Combine(old, f), Path.Combine(addons, f)); } catch { }
                CleanStage(stage, old);
                throw;
            }
            if (movedOut.Count > 0 && !ToBin(old)) placed.Left = old;
            CleanStage(stage, old);
            return placed;
        }

        // Its folders out of AddOns, together to the Recycle Bin. Null when
        // done, else where they are.
        public static string Remove(string addons, string[] folders, string label)
        {
            string stage = Stage(addons), old = Path.Combine(stage, Plain(label + " (uninstalled)"));
            Directory.CreateDirectory(old);
            List<string> moved = new List<string>();
            try
            {
                foreach (string f in folders ?? new string[0])
                {
                    if (!SafeFolder(f)) continue;
                    string there = Path.Combine(addons, f);
                    if (!Directory.Exists(there)) continue;
                    try { Directory.Move(there, Path.Combine(old, f)); }
                    catch (Exception why) { throw InUse(f, why); }
                    moved.Add(f);
                }
            }
            catch
            {
                foreach (string f in moved) try { Directory.Move(Path.Combine(old, f), Path.Combine(addons, f)); } catch { }
                CleanStage(stage, old);
                throw;
            }
            string left = null;
            if (moved.Count > 0 && !ToBin(old)) left = old;
            CleanStage(stage, old);
            return left;
        }

        // The unpacked new files are ours to delete; what came out of AddOns
        // is never deleted here, only sent to the Recycle Bin.
        static void CleanStage(string stage, string old)
        {
            try { string fresh = Path.Combine(stage, "new"); if (Directory.Exists(fresh)) Directory.Delete(fresh, true); } catch { }
            try { if (Directory.Exists(old) && Directory.GetFileSystemEntries(old).Length == 0) Directory.Delete(old); } catch { }
            try { if (Directory.Exists(stage) && Directory.GetFileSystemEntries(stage).Length == 0) Directory.Delete(stage); } catch { }
        }

        // To the Recycle Bin by the shell's delete with undo, no questions
        // (Windows still warns before something too big for the bin would be
        // deleted outright). FUM_TEST_BIN: a folder standing in for the bin.
        public static bool ToBin(string path)
        {
            string bin = Core.Env("FUM_TEST_BIN");
            if (bin != "")
            {
                Directory.CreateDirectory(bin);
                Directory.Move(path, Path.Combine(bin, Guid.NewGuid().ToString("N").Substring(0, 6) + " " + Path.GetFileName(path)));
                return true;
            }
            const uint Delete = 3;
            const ushort Flags = 0x40 | 0x10 | 0x4 | 0x400 | 0x4000;
            string from = Path.GetFullPath(path) + "\0";
            int result;
            bool aborted;
            if (IntPtr.Size == 8)
            {
                Native.FileOp64 op = new Native.FileOp64 { wFunc = Delete, pFrom = from, fFlags = Flags };
                result = Native.FileOperation64(ref op);
                aborted = op.fAnyOperationsAborted != 0;
            }
            else
            {
                Native.FileOp32 op = new Native.FileOp32 { wFunc = Delete, pFrom = from, fFlags = Flags };
                result = Native.FileOperation32(ref op);
                aborted = op.fAnyOperationsAborted != 0;
            }
            return result == 0 && !aborted && !Directory.Exists(path);
        }

        // A folder's .toc as WoW Forever reads it: Folder_Camelot.toc first,
        // then Folder.toc, then any Folder_<game>.toc.
        public static Toc ReadToc(string folderPath)
        {
            if (!Directory.Exists(folderPath)) return null;
            string folder = Path.GetFileName(folderPath.TrimEnd('\\'));
            string[] tries = { folder + "_Camelot.toc", folder + "-Camelot.toc", folder + ".toc" };
            string file = null;
            foreach (string each in tries)
                if (File.Exists(Path.Combine(folderPath, each))) { file = Path.Combine(folderPath, each); break; }
            if (file == null)
                foreach (string each in Directory.GetFiles(folderPath, "*.toc"))
                    if (TocOf(Path.GetFileNameWithoutExtension(each), folder)) { file = each; break; }
            if (file == null) return null;
            Toc toc = new Toc();
            try
            {
                foreach (string line in File.ReadAllLines(file))
                {
                    Match m = Regex.Match(line, @"^##\s*(Title|Version|Interface)\s*:\s*(.*)$");
                    if (!m.Success) continue;
                    string value = m.Groups[2].Value.Trim();
                    if (m.Groups[1].Value == "Title" && toc.Title == null) toc.Title = Regex.Replace(value, @"\|c[0-9A-Fa-f]{8}|\|r", "").Trim();
                    if (m.Groups[1].Value == "Version" && toc.Version == null) toc.Version = value;
                    if (m.Groups[1].Value == "Interface" && toc.Interface == null) toc.Interface = value;
                }
            }
            catch { return null; }
            return toc;
        }

        // The Interface number for WoW Forever (1.6x: 16000 to 16999) in a
        // .toc's line, or null.
        public static string ForeverInterface(string line)
        {
            if (line == null) return null;
            foreach (Match m in Regex.Matches(line, @"\d+"))
            {
                long n;
                if (long.TryParse(m.Value, out n) && n >= 16000 && n < 17000) return m.Value;
            }
            return null;
        }
    }

    class Bar : Control
    {
        float value = -1;
        public Color Fill = Color.Teal;
        public Bar() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true); }
        public float Value { get { return value; } set { this.value = value; Invalidate(); } }
        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.Clear(BackColor);
            if (value >= 0)
                using (SolidBrush brush = new SolidBrush(Fill))
                    e.Graphics.FillRectangle(brush, 0, 0, Width * Math.Min(1f, value), Height);
        }
    }

    // A tick drawn like the list's Auto update one: the flat CheckBox's own
    // check is barely seen on a dark window.
    class DarkTick : CheckBox
    {
        public Color Well, Rim, Mark, Words;
        public float K = 1;

        public DarkTick()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.Clear(BackColor);
            int size = (int)Math.Round(14 * K);
            Rectangle box = new Rectangle(0, (Height - size) / 2, size, size);
            using (SolidBrush well = new SolidBrush(Well)) e.Graphics.FillRectangle(well, box);
            using (Pen rim = new Pen(Checked ? Mark : Rim)) e.Graphics.DrawRectangle(rim, box);
            if (Checked)
            {
                e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
                using (Pen mark = new Pen(Mark, Math.Max(1.5f, 2f * K)))
                    e.Graphics.DrawLines(mark, new[] { new PointF(box.X + size * 0.22f, box.Y + size * 0.52f), new PointF(box.X + size * 0.42f, box.Y + size * 0.72f), new PointF(box.X + size * 0.8f, box.Y + size * 0.28f) });
            }
            TextRenderer.DrawText(e.Graphics, Text, Font, new Rectangle(size + (int)(7 * K), 0, Width, Height), Words,
                TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.NoPrefix);
        }
    }

    class MainForm : Form
    {
        static readonly Color CBack = Color.FromArgb(17, 19, 23);
        static readonly Color CPanel = Color.FromArgb(25, 28, 34);
        static readonly Color CRow = Color.FromArgb(29, 33, 40);
        static readonly Color CPick = Color.FromArgb(31, 54, 56);
        static readonly Color CLine = Color.FromArgb(50, 55, 64);
        static readonly Color CText = Color.FromArgb(228, 230, 234);
        static readonly Color CDim = Color.FromArgb(136, 142, 152);
        static readonly Color CAccent = Color.FromArgb(70, 200, 170);
        static readonly Color CGold = Color.FromArgb(236, 192, 92);
        static readonly Color CRed = Color.FromArgb(238, 104, 92);
        static readonly Color CGreen = Color.FromArgb(100, 212, 124);

        static readonly int[] Widths = { 270, 110, 110, 160, 90 };
        static readonly string[] Titles = { "Addon", "Installed", "Latest", "State", "Auto update" };
        static readonly TimeSpan IndexEvery = TimeSpan.FromHours(6);

        readonly bool startHidden, shotMode;
        readonly float k;
        readonly Font bold, small;
        List<TrackedAddon> addons;
        readonly List<TrackedAddon> available = new List<TrackedAddon>();   // guides on the list not installed
        readonly List<TrackedAddon> availableGit = new List<TrackedAddon>();   // GitHub guides (ours, or found) not installed
        readonly Dictionary<string, TrackedAddon> gitGuides = new Dictionary<string, TrackedAddon>(StringComparer.OrdinalIgnoreCase);
        DateTime guidesAt = DateTime.MinValue, packAt = DateTime.MinValue;
        PackIndex index;
        string indexProblem;
        DateTime indexAt = DateTime.MinValue;
        string game;
        bool busy, quitting, toldTray, shotTaken, guidesTab;
        readonly List<TrackedAddon> waiting = new List<TrackedAddon>();
        DateTime closedSince = DateTime.MinValue;

        readonly ListView list = new ListView();
        readonly Panel heads = new Panel(), detailBox = new Panel();
        readonly Label gameLine = new Label(), status = new Label(), details = new Label();
        readonly LinkLabel repoLink = new LinkLabel(), changeLink = new LinkLabel(), openLink = new LinkLabel();
        readonly Button checkButton = new Button(), addButton = new Button(), installButton = new Button(),
            updateAllButton = new Button(), uninstallButton = new Button(), removeButton = new Button(),
            addonsTabButton = new Button(), guidesTabButton = new Button(), findButton = new Button();
        readonly DarkTick startBox = new DarkTick(), trayBox = new DarkTick();
        readonly Bar bar = new Bar();
        readonly NotifyIcon tray = new NotifyIcon();
        readonly System.Windows.Forms.Timer first = new System.Windows.Forms.Timer(), every = new System.Windows.Forms.Timer(), watch = new System.Windows.Forms.Timer();

        int S(float v) { return (int)Math.Round(v * k); }

        public MainForm(bool hidden)
        {
            startHidden = hidden;
            shotMode = Core.Env("FUM_SHOT") != "";
            using (Graphics g = Graphics.FromHwnd(IntPtr.Zero)) k = g.DpiX / 96f;
            Text = "ForeverUI Manager";
            Font = new Font("Segoe UI", 9f);
            bold = new Font("Segoe UI Semibold", 9.5f);
            small = new Font("Segoe UI", 8.25f);
            BackColor = CBack;
            ForeColor = CText;
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            AutoScaleMode = AutoScaleMode.None;
            ClientSize = new Size(S(780), S(548));
            StartPosition = FormStartPosition.CenterScreen;
            Icon = AppIcon();
            if (shotMode)
            {
                StartPosition = FormStartPosition.Manual;
                Location = new Point(-S(3000), S(40));
                ShowInTaskbar = false;
            }

            Build();
            Pack.LoadHeld();
            addons = Store.Load();
            game = Game.Folder();
            index = Packs.Held();
            Available();
            guidesTab = Core.Env("FUM_SHOT_TAB") == "guides";
            ShowGame();
            ShowTabs();
            Fill();
            SetUpTray();
            startBox.Checked = Core.Setting("startWithWindows", "1") == "1";
            trayBox.Checked = Core.Setting("closeToTray", "1") == "1";
            Core.SetRunKey(startBox.Checked);
            startBox.CheckedChanged += delegate { Core.SetSetting("startWithWindows", startBox.Checked ? "1" : "0"); Core.SetRunKey(startBox.Checked); };
            trayBox.CheckedChanged += delegate { Core.SetSetting("closeToTray", trayBox.Checked ? "1" : "0"); };

            first.Interval = shotMode ? 300 : 1500;
            first.Tick += delegate { first.Stop(); CheckAll(false); };
            first.Start();
            every.Interval = 30 * 60 * 1000;
            every.Tick += delegate { if (!busy) CheckAll(false); };
            every.Start();
            watch.Interval = 5000;
            watch.Tick += delegate { WatchGame(); };
            Status(game == null ? "WoW Forever was not found: use Change... to pick its folder." : "Ready.");
        }

        // Started by Windows (--tray): the window waits in the tray.
        protected override void SetVisibleCore(bool value)
        {
            if (startHidden && !IsHandleCreated)
            {
                CreateHandle();
                value = false;
            }
            base.SetVisibleCore(value);
        }

        protected override bool ShowWithoutActivation { get { return shotMode; } }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            int dark = 1;
            try { Native.DwmSetWindowAttribute(Handle, 20, ref dark, 4); } catch { }
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == Native.ShowMe) ShowMe();
            base.WndProc(ref m);
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (!quitting && e.CloseReason == CloseReason.UserClosing && trayBox.Checked)
            {
                e.Cancel = true;
                Hide();
                if (!toldTray)
                {
                    toldTray = true;
                    tray.ShowBalloonTip(4000, "ForeverUI Manager", "Still here in the tray, keeping your addons up to date. Right-click for Exit.", ToolTipIcon.Info);
                }
                return;
            }
            tray.Visible = false;
            base.OnFormClosing(e);
        }

        void ShowMe()
        {
            Show();
            if (WindowState == FormWindowState.Minimized) WindowState = FormWindowState.Normal;
            Activate();
        }

        static Icon appIcon;

        static Icon AppIcon()
        {
            if (appIcon != null) return appIcon;
            using (Bitmap picture = new Bitmap(64, 64))
            {
                using (Graphics g = Graphics.FromImage(picture))
                {
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                    using (GraphicsPath shape = Rounded(new RectangleF(2, 2, 60, 60), 14))
                    using (LinearGradientBrush fill = new LinearGradientBrush(new PointF(0, 0), new PointF(64, 64), Color.FromArgb(80, 220, 186), Color.FromArgb(24, 120, 104)))
                        g.FillPath(fill, shape);
                    using (Font font = new Font("Segoe UI", 38, FontStyle.Bold, GraphicsUnit.Pixel))
                    using (StringFormat centre = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
                        g.DrawString("F", font, Brushes.White, new RectangleF(0, 2, 64, 62), centre);
                }
                IntPtr handle = picture.GetHicon();
                appIcon = (Icon)Icon.FromHandle(handle).Clone();
                Native.DestroyIcon(handle);
            }
            return appIcon;
        }

        static GraphicsPath Rounded(RectangleF r, float radius)
        {
            GraphicsPath path = new GraphicsPath();
            float d = radius * 2;
            path.AddArc(r.X, r.Y, d, d, 180, 90);
            path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            path.CloseFigure();
            return path;
        }

        void Build()
        {
            Label title = new Label { Text = "ForeverUI Manager", Font = new Font("Segoe UI Semibold", 15f), ForeColor = CText, AutoSize = true, Location = new Point(S(17), S(10)) };
            Controls.Add(title);
            Label tagline = new Label { Text = "v" + Core.Version + "  ·  WoW Forever addons, straight from their GitHub releases", Font = small, ForeColor = CDim, AutoSize = true, Location = new Point(S(20), S(44)) };
            Controls.Add(tagline);
            Style(checkButton, "Check now", 640, 16, 120);
            checkButton.Click += delegate { CheckAll(true); };

            gameLine.Location = new Point(S(20), S(72));
            gameLine.Size = new Size(S(560), S(18));
            gameLine.AutoEllipsis = true;
            gameLine.ForeColor = CDim;
            Controls.Add(gameLine);
            Link(changeLink, "Change...", 610, 72, delegate { PickGame(); });
            Link(openLink, "Open AddOns", 678, 72, delegate
            {
                string folder = AddOns();
                if (folder != null && Directory.Exists(folder)) Process.Start("explorer.exe", "\"" + folder + "\"");
            });

            Style(addonsTabButton, "Addons", 20, 100, 110);
            addonsTabButton.Click += delegate { SwitchTab(false); };
            Style(guidesTabButton, "Polestar guides", 136, 100, 140);
            guidesTabButton.Click += delegate { SwitchTab(true); };

            heads.Location = new Point(S(20), S(136));
            heads.Size = new Size(S(740), S(26));
            heads.BackColor = CPanel;
            heads.Paint += PaintHeads;
            Controls.Add(heads);

            list.Location = new Point(S(20), S(162));
            list.Size = new Size(S(740), S(186));
            list.View = View.Details;
            list.HeaderStyle = ColumnHeaderStyle.None;
            list.FullRowSelect = true;
            list.MultiSelect = false;
            list.HideSelection = false;
            list.BorderStyle = BorderStyle.None;
            list.BackColor = CPanel;
            list.ForeColor = CText;
            list.OwnerDraw = true;
            list.SmallImageList = new ImageList { ImageSize = new Size(1, S(30)) };
            // The first column gives up the room of a scroll bar, so a long list never scrolls sideways.
            for (int i = 0; i < Widths.Length; i++) list.Columns.Add(Titles[i], S(Widths[i]) - (i == 0 ? SystemInformation.VerticalScrollBarWidth : 0));
            list.HandleCreated += delegate { try { Native.SetWindowTheme(list.Handle, "DarkMode_Explorer", null); } catch { } };
            list.DrawColumnHeader += delegate(object sender, DrawListViewColumnHeaderEventArgs e) { e.DrawDefault = false; };
            list.DrawItem += delegate(object sender, DrawListViewItemEventArgs e) { e.DrawDefault = false; };
            list.DrawSubItem += DrawCell;
            list.SelectedIndexChanged += delegate { ShowPicked(); Buttons(); };
            list.MouseClick += ClickList;
            typeof(Control).GetProperty("DoubleBuffered", BindingFlags.NonPublic | BindingFlags.Instance).SetValue(list, true, null);
            Controls.Add(list);

            detailBox.Location = new Point(S(20), S(356));
            detailBox.Size = new Size(S(740), S(78));
            detailBox.BackColor = CPanel;
            Controls.Add(detailBox);
            repoLink.Location = new Point(S(12), S(8));
            repoLink.AutoSize = true;
            repoLink.Font = bold;
            repoLink.LinkColor = repoLink.ActiveLinkColor = repoLink.VisitedLinkColor = CAccent;
            repoLink.LinkBehavior = LinkBehavior.HoverUnderline;
            repoLink.LinkClicked += delegate
            {
                TrackedAddon a = Picked();
                if (a == null) return;
                if (!a.IsPack) Process.Start("https://github.com/" + a.Repo + "/releases");
                else Process.Start(a.Entry != null && a.Entry.Homepage != null ? a.Entry.Homepage : Packs.Base);
            };
            detailBox.Controls.Add(repoLink);
            details.Location = new Point(S(12), S(30));
            details.Size = new Size(S(716), S(46));
            details.ForeColor = CDim;
            details.Font = small;
            details.UseMnemonic = false;
            detailBox.Controls.Add(details);

            Style(addButton, "Add from GitHub...", 20, 444, 150);
            addButton.Click += delegate { AddFromGitHub(); };
            Style(findButton, "Find on GitHub", 510, 444, 130);
            findButton.Click += delegate { FindOnGitHub(); };
            Style(installButton, "Install", 180, 444, 110);
            installButton.Click += delegate { InstallPicked(); };
            Style(updateAllButton, "Update all", 300, 444, 110);
            updateAllButton.Click += delegate { UpdateAll(); };
            Style(uninstallButton, "Uninstall", 420, 444, 110);
            uninstallButton.Click += delegate { UninstallPicked(); };
            Style(removeButton, "Remove from list", 610, 444, 150);
            removeButton.Click += delegate { RemovePicked(); };

            bar.Location = new Point(S(20), S(484));
            bar.Size = new Size(S(740), Math.Max(2, S(3)));
            bar.BackColor = CBack;
            bar.Fill = CAccent;
            Controls.Add(bar);
            status.Location = new Point(S(20), S(492));
            status.Size = new Size(S(740), S(20));
            status.AutoEllipsis = true;
            status.UseMnemonic = false;
            Controls.Add(status);

            Tick(startBox, "Start with Windows", 20, 518);
            Tick(trayBox, "Close to the tray", 190, 518);
        }

        void Style(Button b, string text, int x, int y, int w)
        {
            Style(b, text, x, y, w, this);
        }

        void Style(Button b, string text, int x, int y, int w, Control into)
        {
            b.Text = text;
            b.Location = new Point(S(x), S(y));
            b.Size = new Size(S(w), S(30));
            b.FlatStyle = FlatStyle.Flat;
            b.FlatAppearance.BorderColor = CLine;
            b.FlatAppearance.MouseOverBackColor = Color.FromArgb(40, 46, 54);
            b.FlatAppearance.MouseDownBackColor = Color.FromArgb(30, 64, 60);
            b.BackColor = CPanel;
            b.ForeColor = CText;
            b.UseVisualStyleBackColor = false;
            b.Cursor = Cursors.Hand;
            into.Controls.Add(b);
        }

        void Link(LinkLabel link, string text, int x, int y, Action click)
        {
            link.Text = text;
            link.AutoSize = true;
            link.Location = new Point(S(x), S(y));
            link.LinkColor = link.ActiveLinkColor = link.VisitedLinkColor = CAccent;
            link.DisabledLinkColor = CDim;
            link.LinkBehavior = LinkBehavior.HoverUnderline;
            link.LinkClicked += delegate { click(); };
            Controls.Add(link);
        }

        void Tick(DarkTick box, string text, int x, int y)
        {
            box.Text = text;
            box.AutoSize = false;
            box.K = k;
            box.Location = new Point(S(x), S(y));
            box.Size = new Size(S(21) + TextRenderer.MeasureText(text, Font).Width, S(22));
            box.Well = CBack;
            box.Rim = CLine;
            box.Mark = CAccent;
            box.Words = CDim;
            box.BackColor = CBack;
            box.Cursor = Cursors.Hand;
            Controls.Add(box);
        }

        void SwitchTab(bool guides)
        {
            if (guidesTab == guides) return;
            guidesTab = guides;
            ShowTabs();
            Fill();
            if (guides && (index == null || guidesAt == DateTime.MinValue) && !busy) CheckAll(false);
        }

        void Place(Button b, int x, int w)
        {
            b.Location = new Point(S(x), b.Location.Y);
            b.Width = S(w);
        }

        void ShowTabs()
        {
            foreach (Button tab in new[] { addonsTabButton, guidesTabButton })
            {
                bool on = (tab == guidesTabButton) == guidesTab;
                tab.BackColor = on ? CPick : CBack;
                tab.ForeColor = on ? CText : CDim;
                tab.FlatAppearance.BorderColor = on ? CAccent : CLine;
            }
            // The guides' row has one button more: Find on GitHub.
            findButton.Visible = guidesTab;
            if (guidesTab)
            {
                Place(addButton, 20, 150); Place(installButton, 180, 100); Place(updateAllButton, 290, 100);
                Place(uninstallButton, 400, 100); Place(findButton, 510, 130); Place(removeButton, 650, 110);
                removeButton.Text = "Remove";
            }
            else
            {
                Place(addButton, 20, 150); Place(installButton, 180, 110); Place(updateAllButton, 300, 110);
                Place(uninstallButton, 420, 110); Place(removeButton, 610, 150);
                removeButton.Text = "Remove from list";
            }
            heads.Invalidate();
        }

        void PaintHeads(object sender, PaintEventArgs e)
        {
            int x = 0;
            for (int i = 0; i < list.Columns.Count; i++)
            {
                string title = i == 0 && guidesTab ? "Guide" : Titles[i];
                TextRenderer.DrawText(e.Graphics, title, small, new Rectangle(x + S(10), 0, list.Columns[i].Width - S(12), heads.Height), CDim,
                    TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.EndEllipsis);
                x += list.Columns[i].Width;
            }
            using (Pen line = new Pen(CLine)) e.Graphics.DrawLine(line, 0, heads.Height - 1, heads.Width, heads.Height - 1);
        }

        void DrawCell(object sender, DrawListViewSubItemEventArgs e)
        {
            TrackedAddon a = (TrackedAddon)e.Item.Tag;
            int x = 0;
            for (int i = 0; i < e.ColumnIndex; i++) x += list.Columns[i].Width;
            // Column 0's bounds span the whole row: each cell from the columns' widths.
            Rectangle cell = new Rectangle(e.Item.Bounds.X + x, e.Bounds.Y, list.Columns[e.ColumnIndex].Width, e.Bounds.Height);
            using (SolidBrush back = new SolidBrush(e.Item.Selected ? CPick : (e.ItemIndex % 2 == 0 ? CPanel : CRow)))
                e.Graphics.FillRectangle(back, cell);
            Rectangle text = new Rectangle(cell.X + S(10), cell.Y, cell.Width - S(14), cell.Height);
            TextFormatFlags flags = TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix;
            switch (e.ColumnIndex)
            {
                case 0:
                    {
                        if (!guidesTab)
                        {
                            // Ticked: Install all puts it in. An installed or required one stays ticked.
                            int size = S(14);
                            Rectangle box = new Rectangle(text.X, cell.Y + (cell.Height - size) / 2, size, size);
                            bool on = Ticked(a), locked = a.Tag != null || a.Required;
                            Color tone = on ? (locked ? CDim : CAccent) : CLine;
                            using (SolidBrush well = new SolidBrush(CBack)) e.Graphics.FillRectangle(well, box);
                            using (Pen rim = new Pen(tone)) e.Graphics.DrawRectangle(rim, box);
                            if (on) Check(e.Graphics, box, tone);
                            text = new Rectangle(box.Right + S(8), text.Y, Math.Max(0, text.Right - box.Right - S(8)), text.Height);
                        }
                        Size name = TextRenderer.MeasureText(e.Graphics, a.Name, bold, text.Size, flags);
                        TextRenderer.DrawText(e.Graphics, a.Name, bold, text, CText, flags);
                        Rectangle by = new Rectangle(text.X + name.Width + S(2), text.Y, Math.Max(0, text.Width - name.Width - S(2)), text.Height);
                        string from = !guidesTab ? "" : a.IsPack ? "  ·  polestar.guide" : a.Source == "search" ? "  ·  found on GitHub" : "  ·  GitHub";
                        if (by.Width > S(30) && a.By != "") TextRenderer.DrawText(e.Graphics, "by " + a.By + from, small, by, CDim, flags);
                        break;
                    }
                case 1:
                    TextRenderer.DrawText(e.Graphics, a.Tag != null ? Short(a.Tag) : (a.Found != null ? a.Found + " (by hand)" : "-"), Font, text, a.Tag != null ? CText : CDim, flags);
                    break;
                case 2:
                    TextRenderer.DrawText(e.Graphics, a.Known != null ? Short(a.Known) : "-", Font, text, CText, flags);
                    break;
                case 3:
                    {
                        Color colour;
                        string said = StateOf(a, out colour);
                        TextRenderer.DrawText(e.Graphics, said, Font, text, colour, flags);
                        break;
                    }
                case 4:
                    {
                        int size = S(14);
                        Rectangle box = new Rectangle(text.X, cell.Y + (cell.Height - size) / 2, size, size);
                        using (SolidBrush well = new SolidBrush(CBack)) e.Graphics.FillRectangle(well, box);
                        using (Pen rim = new Pen(a.Auto ? CAccent : CLine)) e.Graphics.DrawRectangle(rim, box);
                        if (a.Auto) Check(e.Graphics, box, CAccent);
                        TextRenderer.DrawText(e.Graphics, a.Auto ? "On" : "Off", small, new Rectangle(box.Right + S(6), cell.Y, cell.Width, cell.Height), a.Auto ? CText : CDim, flags);
                        break;
                    }
            }
        }

        void Check(Graphics g, Rectangle box, Color colour)
        {
            float size = box.Width;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (Pen mark = new Pen(colour, Math.Max(1.5f, 2f * k)))
                g.DrawLines(mark, new[] { new PointF(box.X + size * 0.22f, box.Y + size * 0.52f), new PointF(box.X + size * 0.42f, box.Y + size * 0.72f), new PointF(box.X + size * 0.8f, box.Y + size * 0.28f) });
            g.SmoothingMode = SmoothingMode.None;
        }

        static bool Ticked(TrackedAddon a) { return a.Want || a.Tag != null || a.Required; }

        // A series' tag in a column: its version alone ("quests-audio/v2.5.0": "v2.5.0").
        static string Short(string tag) { return tag.Substring(tag.LastIndexOf('/') + 1); }

        // Ticked and not in AddOns yet: what Install all puts in.
        List<TrackedAddon> ToInstall()
        {
            return guidesTab ? new List<TrackedAddon>() : addons.FindAll(a => !a.WithGuides && a.Tag == null && Ticked(a));
        }

        string StateOf(TrackedAddon a, out Color colour)
        {
            if (a.Busy != null) { colour = CAccent; return a.Busy; }
            if (a.Pulled != null && a.Tag == null) { colour = CRed; return "Pulled by the site"; }
            if (a.Problem != null) { colour = CRed; return "Check failed"; }
            if (a.Tag == null)
            {
                if (a.WithGuides && Blocked(a) != null) { colour = CDim; return "Can't install yet"; }
                colour = a.Found != null ? CGold : CDim;
                // Its download's size, before it goes in (a voice pack is 1.4 GB).
                return a.Found != null ? "In AddOns by hand" : "Not installed" + (!a.WithGuides && a.Latest != null && a.Latest.Size > 0 ? ", " + Bytes(a.Latest.Size) : "");
            }
            if (a.Missing) { colour = CRed; return "Folders missing"; }
            if (a.UpdateWaits)
            {
                colour = CGold;
                return waiting.Contains(a) ? "Waits for the game" : "Update available";
            }
            colour = CGreen;
            return a.Known == null ? "Installed" : "Up to date";
        }

        void ClickList(object sender, MouseEventArgs e)
        {
            ListViewHitTestInfo hit = list.HitTest(e.Location);
            if (hit.Item == null || hit.SubItem == null) return;
            int column = hit.Item.SubItems.IndexOf(hit.SubItem);
            if (column == 0 && !guidesTab && e.X - hit.Item.Bounds.X < S(32))
            {
                Toggle((TrackedAddon)hit.Item.Tag);
                return;
            }
            if (column != 4) return;
            TrackedAddon a = (TrackedAddon)hit.Item.Tag;
            a.Auto = !a.Auto;
            if (addons.Contains(a)) Store.Save(addons);
            list.Invalidate();
            Status(a.Name + (a.Auto
                ? (a.IsPack ? ": a new version goes in by itself, a day after it is out, with the game closed." : ": updates by itself when a new release comes out.")
                : ": updates only when you click Update."));
        }

        void Toggle(TrackedAddon a)
        {
            if (a.Tag != null) { Status(a.Name + " is installed: Uninstall takes it out of AddOns."); return; }
            if (a.Required) { Status(a.Name + " is part of the ForeverUI look: it cannot be left out."); return; }
            a.Want = !a.Want;
            Store.Save(addons);
            list.Invalidate();
            Buttons();
            long size = a.Latest != null ? a.Latest.Size : -1;
            Status(a.Want ? a.Name + " is ticked: Install all puts it in" + (size > 0 ? " (" + Bytes(size) + ")." : ".") : a.Name + " is left out: Install all skips it.");
        }

        string AddOns() { return Game.AddOns(game); }

        TrackedAddon Picked()
        {
            return list.SelectedItems.Count > 0 ? (TrackedAddon)list.SelectedItems[0].Tag : null;
        }

        void Pick(TrackedAddon a)
        {
            foreach (ListViewItem item in list.Items) item.Selected = item.Tag == a;
        }

        void ShowGame()
        {
            if (game == null)
            {
                gameLine.Text = "WoW Forever not found. Use Change... to pick its folder (_forever_, with Wow.exe).";
                gameLine.ForeColor = CRed;
                return;
            }
            string version = Game.Version(game);
            gameLine.Text = "WoW Forever" + (version != "" ? " " + version : "") + "  ·  " + AddOns();
            gameLine.ForeColor = CDim;
        }

        // The guides the list offers that are not installed; an installed
        // one takes its entry.
        void Available()
        {
            // GitHub's: ours (the pack's), and any a search found, not on the list yet.
            availableGit.Clear();
            KnownRepo[] ours = KnownRepo.GuideRepos();
            foreach (string gone in gitGuides.Where(g => g.Value.Source == "list" && !ours.Any(k => string.Equals(k.Repo, g.Key, StringComparison.OrdinalIgnoreCase))).Select(g => g.Key).ToList())
                gitGuides.Remove(gone);
            foreach (KnownRepo known in ours)
                if (!gitGuides.ContainsKey(known.Repo)) gitGuides[known.Repo] = TrackedAddon.ForRepo(known.Repo);
            foreach (TrackedAddon g in gitGuides.Values)
                if (!addons.Exists(a => string.Equals(a.Repo, g.Repo, StringComparison.OrdinalIgnoreCase))) availableGit.Add(g);

            available.Clear();
            foreach (TrackedAddon a in addons) if (a.IsPack) a.Entry = null;
            if (index == null) return;
            foreach (PackEntry entry in index.Packs)
            {
                TrackedAddon mine = addons.Find(a => a.IsPack && a.PackId == entry.Id);
                if (mine != null)
                {
                    mine.Show(entry);
                    // A pulled guide can come back with a version the site has not pulled.
                    if (mine.Tag == null && index.Revocation(entry.Id, entry.Uid, entry.Version) == null) mine.Pulled = null;
                }
                else available.Add(TrackedAddon.ForPack(entry));
            }
        }

        List<TrackedAddon> Rows()
        {
            if (!guidesTab) return addons.FindAll(a => !a.WithGuides);
            List<TrackedAddon> rows = addons.FindAll(a => a.WithGuides);
            rows.AddRange(available);
            rows.AddRange(availableGit);
            return rows;
        }

        // What AddOns holds of each addon: its folders still there, its
        // .toc's title and Interface, a copy put there by hand.
        void Probe(TrackedAddon a)
        {
            a.Found = null;
            a.Missing = false;
            a.Interface = null;
            string folder = AddOns();
            if (folder == null) return;
            string main = a.RepoName;
            if (a.Folders != null && a.Folders.Length > 0)
            {
                main = a.Folders.FirstOrDefault(f => string.Equals(f, a.RepoName, StringComparison.OrdinalIgnoreCase))
                    ?? a.Folders.OrderBy(f => f.Length).First();
                foreach (string f in a.Folders)
                    if (!Directory.Exists(Path.Combine(folder, f))) a.Missing = true;
            }
            if (a.IsPack && a.Tag == null && Packs.Owner(Path.Combine(folder, main)) != a.PackId) return;
            Toc toc = Installer.ReadToc(Path.Combine(folder, main));
            if (toc == null) return;
            if (a.Tag == null) a.Found = toc.Version ?? "?";
            // A pack's addon keeps the pack's name ("Spoken Bosses Audio", not its .toc's "Spoken Audio: Bosses").
            if (!a.IsPack && a.Source != "pack" && !string.IsNullOrEmpty(toc.Title)) a.Title = Regex.Replace(toc.Title, "^Polestar (Community|Pack): ", "");
            a.Interface = toc.Interface;
            a.Code = a.Guide && a.Tag != null ? Packs.Compiled(Path.Combine(folder, main)) : null;
        }

        void Fill()
        {
            TrackedAddon keep = Picked();
            ReadGame();
            list.BeginUpdate();
            list.Items.Clear();
            foreach (TrackedAddon a in Rows())
            {
                Probe(a);
                ListViewItem item = new ListViewItem(new[] { a.Repo, "", "", "", "" });
                item.Tag = a;
                list.Items.Add(item);
            }
            list.EndUpdate();
            ListViewItem again = list.Items.Cast<ListViewItem>().FirstOrDefault(i => i.Tag == keep);
            if (again == null && list.Items.Count > 0) again = list.Items[0];
            if (again != null) again.Selected = true;
            ShowPicked();
            Buttons();
        }

        static string Day(string iso)
        {
            DateTime when;
            return DateTime.TryParse(iso, CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out when)
                ? when.ToLocalTime().ToString("d MMM yyyy", CultureInfo.InvariantCulture) : iso;
        }

        static string Bytes(long bytes) { return Core.Bytes(bytes); }

        // Read again at each Fill, not at each paint.
        string polestarHave;
        int gameInterface;

        string PolestarVersion() { return polestarHave; }

        void ReadGame()
        {
            Toc toc = AddOns() == null ? null : Installer.ReadToc(Path.Combine(AddOns(), "Polestar"));
            polestarHave = toc == null ? null : toc.Version;
            gameInterface = game == null ? 0 : Game.Interface(game);
        }

        // Why a guide cannot go in now (pulled, made for another game version,
        // needs a newer Polestar); null when it can.
        string Blocked(TrackedAddon a)
        {
            if (!a.IsPack)
                return a.Guide && a.Tag == null && PolestarVersion() == null ? "it needs Polestar: install Polestar first (Addons tab)" : null;
            PackEntry e = a.Entry;
            if (e == null) return "polestar.guide's list no longer has it";
            PackRevoke pulled = index == null ? null : index.Revocation(e.Id, e.Uid, e.Version);
            if (pulled != null) return "polestar.guide pulled this version: " + pulled.Reason;
            int iface = gameInterface;
            if (e.Toc > 0 && iface > 0 && e.Toc != iface) return "it is made for Interface " + e.Toc + " and your WoW Forever is " + iface;
            string have = PolestarVersion();
            if (have == null) return "it needs Polestar: install Polestar first (Addons tab)";
            if (e.MinPolestar != null && Core.CompareVersions(have, e.MinPolestar) < 0) return "it needs Polestar " + e.MinPolestar + " or newer (you have " + have + ")";
            return null;
        }

        void ShowPicked()
        {
            TrackedAddon a = Picked();
            if (a == null)
            {
                repoLink.Text = "";
                details.Text = guidesTab
                    ? (index == null ? "polestar.guide's guide list is not here yet" + (indexProblem != null ? ": " + indexProblem : ".") : "polestar.guide lists no guides right now.")
                    : "Add an addon with its GitHub link: Add from GitHub...";
                return;
            }
            List<string> lines = new List<string>();
            if (a.IsPack)
            {
                repoLink.Text = "polestar.guide  ·  " + a.PackId;
                if (a.Pulled != null && a.Tag == null) lines.Add("Pulled by polestar.guide: " + a.Pulled.TrimEnd('.') + ". Its folders went to the Recycle Bin.");
                PackEntry e = a.Entry;
                if (e != null)
                {
                    lines.Add("Latest " + e.Version + (e.Published != null ? ", out " + Day(e.Published) : "") + "  ·  " + Bytes(e.Size)
                        + "  ·  " + (e.Reviewed ? "reviewed by the site" : "not reviewed yet") + "  ·  from the signed guide list"
                        + (e.Changelog != "" ? "  ·  " + e.Changelog.Split('\n')[0].Trim() : ""));
                    string why = Blocked(a);
                    if (why != null && a.Tag == null && a.Pulled == null) lines.Add("Can't install: " + why.TrimEnd('.') + ".");
                    else if (e.MinPolestar != null) lines.Add("Needs Polestar " + e.MinPolestar + " or newer (you have " + (PolestarVersion() ?? "none") + ").");
                }
            }
            else
            {
                repoLink.Text = "github.com/" + a.Repo;
                if (a.Guide)
                    lines.Add((a.Source == "list" ? "A Polestar guide on GitHub, on ForeverUI Manager's list" : a.Source == "search" ? "A Polestar guide a GitHub search found: not on ForeverUI Manager's list" : "A Polestar guide on GitHub, added by you")
                        + (a.Betas ? "  ·  test versions (pre-releases) too" : "")
                        + (a.Tag == null ? "" : a.Code == null ? "  ·  only what Polestar's guide compiler makes" : "  ·  carries " + a.Code));
                if (a.Problem != null) lines.Add("Last check failed: " + a.Problem + ".");
                Release r = a.Latest;
                if (r != null)
                    lines.Add("Latest " + r.Tag + (r.Test ? " (test version)" : "") + (r.Published != null ? ", out " + Day(r.Published) : "") + "  ·  " + r.ZipName
                        + (r.Size > 0 ? " (" + Bytes(r.Size) + ")" : "") + "  ·  " + r.PickedBy);
                string why = a.Guide && a.Tag == null ? Blocked(a) : null;
                if (why != null) lines.Add("Can't install: " + why + ".");
            }
            if (a.Tag != null)
            {
                string iface = Installer.ForeverInterface(a.Interface);
                lines.Add("Installed " + a.Tag + (a.InstalledAt != null ? " on " + a.InstalledAt : "") + "  ·  " + a.Folders.Length + " folder(s) in AddOns"
                    + (a.Missing ? ", some gone (Install puts them back)" : "")
                    + (a.IsPack || a.Interface == null ? "" : iface != null ? "  ·  its .toc is for WoW Forever (" + iface + ")" : "  ·  its .toc lists no WoW Forever Interface"));
            }
            else if (a.Found != null) lines.Add("In AddOns (version " + a.Found + "), put there by hand or by another app. Install replaces it.");
            else if (!a.IsPack || a.Pulled == null)
                lines.Add(a.WithGuides ? "Not installed yet." : Ticked(a) ? "Not installed yet: ticked, so Install all puts it in." : "Not installed: not ticked, so Install all leaves it out (tick its box to have it).");
            if (a.Source == "pack" && lines.Count > 0)
                lines[lines.Count - 1] += a.Required ? "  ·  Part of the ForeverUI look." : "  ·  An extra of the ForeverUI pack.";
            details.Text = string.Join("\n", lines.ToArray());
        }

        void Buttons()
        {
            TrackedAddon a = Picked();
            bool can = !busy && game != null;
            installButton.Text = a == null || a.Tag == null || a.Missing ? "Install" : a.UpdateWaits ? "Update" : "Reinstall";
            installButton.Enabled = can && a != null && Blocked(a) == null;
            uninstallButton.Enabled = can && a != null && a.Tag != null;
            // Off the list: what was added by hand, and the pack's extras (our
            // guides and the found ones come back by themselves; a required one stays).
            removeButton.Enabled = !busy && a != null && !a.IsPack && addons.Contains(a) && (a.Source == null || a.Source == "pack") && !a.Required;
            findButton.Enabled = !busy;
            bool fresh = ToInstall().Count > 0;
            updateAllButton.Text = fresh ? "Install all" : "Update all";
            updateAllButton.Enabled = can && (fresh || Rows().Exists(x => x.UpdateWaits && !x.Missing));
            checkButton.Enabled = !busy;
            addButton.Enabled = !busy || guidesTab;
            changeLink.Enabled = !busy;
            addonsTabButton.Enabled = guidesTabButton.Enabled = true;
        }

        void Status(string text) { Status(text, CDim); }

        void Status(string text, Color colour)
        {
            status.Text = text;
            status.ForeColor = colour;
        }

        // One job at a time, off the window's thread.
        void Work(string what, Func<object> job, Action<object> done, Action<Exception> failed)
        {
            busy = true;
            Buttons();
            Status(what, CText);
            ThreadPool.QueueUserWorkItem(delegate
            {
                object result = null;
                Exception error = null;
                try { result = job(); }
                catch (Exception why) { error = why; }
                BeginInvoke((Action)delegate
                {
                    busy = false;
                    bar.Value = -1;
                    try
                    {
                        if (error == null) done(result);
                        else if (failed != null) failed(error);
                        else { Status(error.Message, CRed); Core.Log(error.ToString()); }
                    }
                    finally
                    {
                        Buttons();
                        list.Invalidate();
                    }
                });
            });
        }

        void Say(TrackedAddon a, string text, float progress)
        {
            BeginInvoke((Action)delegate
            {
                a.Busy = text;
                bar.Value = progress;
                list.Invalidate();
            });
        }

        class PackSnap
        {
            public TrackedAddon Record;
            public string Id, Uid, Version;
            public string[] Folders;
            public PackRevoke Pull;
            public string Left, Failed;
        }

        // Every addon's newest release from GitHub; polestar.guide's guide
        // list too every 6 hours (or when asked), and any installed guide the
        // site has pulled goes to the Recycle Bin, even with the game open.
        void CheckAll(bool manual)
        {
            if (busy) return;
            List<TrackedAddon> repos = addons.FindAll(a => !a.IsPack);
            // GitHub's guides not installed: only with the guides in view, every 6 hours, or when asked.
            bool wantGuides = manual || (guidesTab && DateTime.Now - guidesAt >= IndexEvery);
            if (wantGuides) repos.AddRange(availableGit);
            bool wantIndex = manual || index == null || DateTime.Now - indexAt >= IndexEvery;
            string addonsFolder = AddOns();
            List<PackSnap> installed = addons.FindAll(a => a.IsPack && a.Tag != null && a.Folders != null)
                .ConvertAll(a => new PackSnap { Record = a, Id = a.PackId, Uid = a.Uid, Version = a.Tag, Folders = a.Folders });
            PackIndex held = index;
            Dictionary<TrackedAddon, object> answers = new Dictionary<TrackedAddon, object>();
            PackIndex fetched = null;
            string fetchProblem = null;
            // The pack's list: at the first check, every 6 hours, or when asked.
            bool wantPack = manual || DateTime.Now - packAt >= IndexEvery;
            List<string> onList = addons.Select(a => a.Key).ToList(), offered = Store.OfferedKeys();
            string packText = null, packFail = null;
            KnownRepo[][] packRead = null;
            Dictionary<string, object> freshAnswers = new Dictionary<string, object>();
            Work("Checking for new versions...", delegate
            {
                if (wantPack)
                {
                    try { packText = Pack.Download(); packRead = Pack.Parse(packText); }
                    catch (Exception why) { packFail = why.Message; Core.Log("pack.json: " + why.Message); }
                    // What it adds to the list, checked in the same round.
                    if (packRead != null)
                        foreach (KnownRepo k in packRead[0])
                            if (!onList.Exists(key => TrackedAddon.SameKey(key, k.Key)) && (k.Required || !Store.Offered(offered, k)))
                            {
                                try { freshAnswers[k.Key] = GitHub.Latest(k.Repo, k.Series, k.Zip, false); }
                                catch (Exception why) { freshAnswers[k.Key] = why.Message; Core.Log("check " + k.Key + ": " + why.Message); }
                            }
                }
                foreach (TrackedAddon a in repos)
                {
                    try { answers[a] = GitHub.Latest(a); }
                    catch (Exception why) { answers[a] = why.Message; Core.Log("check " + a.Repo + ": " + why.Message); }
                }
                if (wantIndex)
                {
                    try { fetched = Packs.Fetch(); }
                    catch (Exception why) { fetchProblem = why.Message; Core.Log("guide list: " + why.Message); }
                }
                PackIndex use = fetched ?? held;
                // Tests only: a pull the signed list cannot be made to say, put in the list held.
                if (use != null && Core.TestMode && Core.Env("FUM_TEST_PULL") != "")
                    foreach (PackSnap snap in installed)
                        if (snap.Id == Core.Env("FUM_TEST_PULL"))
                            use.Revoked.Add(new PackRevoke { Id = snap.Id, Uid = snap.Uid ?? "test", Reason = "Pulled for a test.", Remove = true });
                if (use != null && addonsFolder != null)
                    foreach (PackSnap snap in installed)
                    {
                        snap.Pull = use.Revocation(snap.Id, snap.Uid, snap.Version);
                        if (snap.Pull == null) continue;
                        try { snap.Left = Installer.Remove(addonsFolder, snap.Folders, snap.Id + " " + snap.Version + " pulled"); }
                        catch (Exception why) { snap.Failed = why.Message; }
                    }
                return null;
            }, delegate
            {
                foreach (KeyValuePair<TrackedAddon, object> answer in answers)
                {
                    Release r = answer.Value as Release;
                    answer.Key.Latest = r;
                    answer.Key.Problem = r == null ? (string)answer.Value : null;
                    if (r != null) answer.Key.Known = r.Tag;
                }
                List<TrackedAddon> joined = new List<TrackedAddon>();
                if (packRead != null)
                {
                    try
                    {
                        if (Pack.Use(packText, true)) Core.Log("pack.json read: " + Pack.Addons.Length + " addons, " + Pack.Guides.Length + " guides");
                        packAt = DateTime.Now;
                        joined = Store.Seed(addons);
                        foreach (TrackedAddon a in joined)
                        {
                            object said;
                            if (!freshAnswers.TryGetValue(a.Key, out said)) continue;
                            a.Latest = said as Release;
                            a.Problem = a.Latest == null ? (string)said : null;
                            if (a.Latest != null) a.Known = a.Latest.Tag;
                        }
                    }
                    catch (Exception why) { Core.Log("pack.json not used: " + why.Message); }
                }
                if (wantGuides) guidesAt = DateTime.Now;
                if (fetched != null) { index = fetched; indexAt = DateTime.Now; indexProblem = null; }
                else if (fetchProblem != null) indexProblem = fetchProblem;
                List<string> pulledNames = new List<string>();
                foreach (PackSnap snap in installed)
                {
                    if (snap.Pull == null) continue;
                    if (snap.Failed != null) { snap.Record.Problem = "pulled by polestar.guide, but its folders could not be moved: " + snap.Failed; continue; }
                    snap.Record.Tag = null;
                    snap.Record.Folders = null;
                    snap.Record.Pulled = snap.Pull.Reason;
                    pulledNames.Add(snap.Record.Name);
                    Core.Log("pulled " + snap.Id + " " + snap.Version + ": " + snap.Pull.Reason + (snap.Left != null ? " (left in " + snap.Left + ")" : ""));
                }
                Available();
                Store.Save(addons);
                Fill();
                int fails = repos.Count(a => a.Problem != null), updates = addons.Count(a => a.UpdateWaits);
                if (pulledNames.Count > 0)
                {
                    string said = string.Join(", ", pulledNames.ToArray()) + (pulledNames.Count == 1 ? " was" : " were") + " pulled by polestar.guide; its folders are in the Recycle Bin.";
                    Status(said, CRed);
                    if (!Visible) tray.ShowBalloonTip(6000, "ForeverUI Manager", said, ToolTipIcon.Warning);
                }
                else if (fails > 0) Status(fails == 1 ? "The check failed for " + repos.First(a => a.Problem != null).Name + ": " + repos.First(a => a.Problem != null).Problem + "." : fails + " checks failed (see each one).", CRed);
                else if (guidesTab && fetchProblem != null) Status("The guide list did not come: " + fetchProblem + ".", CRed);
                else if (joined.Count > 0 && addons.Exists(a => a.Tag != null))
                    Status("New in the ForeverUI pack: " + string.Join(", ", joined.Select(a => a.Name).ToArray()) + "." + (joined.Exists(Ticked) ? " Install all puts in the ticked ones." : ""), CGold);
                else if (updates > 0) Status(updates == 1 ? "An update is out." : updates + " updates are out.", CGold);
                else if (!addons.Exists(a => a.Tag != null))
                {
                    List<TrackedAddon> ticked = ToInstall();
                    long size = ticked.Sum(a => a.Latest != null && a.Latest.Size > 0 ? a.Latest.Size : 0);
                    Status("Checked at " + DateTime.Now.ToString("HH:mm") + ". Nothing installed yet: " + (ticked.Count > 0
                        ? "Install all puts in the " + ticked.Count + " ticked addons" + (size > 0 ? " (" + Bytes(size) + ")" : "") + "."
                        : "pick an addon and click Install."), CDim);
                }
                else Status("Checked at " + DateTime.Now.ToString("HH:mm") + ": everything installed is up to date.", CDim);
                if (Core.Env("FUM_SHOT_FIND") == "1") FindOnGitHub();
                else if (!AutoUpdates()) ShotIfAsked();
            }, null);
        }

        // A guide's pins: still the same guide, publisher and folders as when installed.
        static bool SamePins(TrackedAddon a)
        {
            PackEntry e = a.Entry;
            return e != null && a.Uid == e.Uid && a.PublisherId == e.PublisherId
                && a.Folders != null && a.Folders.OrderBy(f => f).SequenceEqual(e.Folders.OrderBy(f => f));
        }

        // Updates by themselves (Auto update on): now with the game closed,
        // else once it has been closed for 8 s. A guide's only a day after
        // its version came out, and only when it is still the same guide.
        // True when some started.
        bool AutoUpdates()
        {
            if (game == null) return false;
            List<TrackedAddon> due = addons.FindAll(a => a.Auto && a.UpdateWaits && !a.Missing && a.Problem == null && a.Latest != null
                && (!a.IsPack || (SamePins(a) && Blocked(a) == null && Packs.Time(a.Entry.Published) != null
                    && DateTime.UtcNow - Packs.Time(a.Entry.Published).Value >= Packs.AutoHold)));
            if (Core.Env("FUM_SHOT_INSTALL") == "1")
            {
                // Tests: what Install all would put in (a ticked one), and nothing else.
                due.AddRange(addons.FindAll(a => !a.IsPack && a.Tag == null && a.Latest != null && Ticked(a) && !due.Contains(a)));
                if (Core.Env("FUM_SHOT_TAB") == "guides")
                {
                    due.AddRange(available.FindAll(a => Blocked(a) == null));
                    due.AddRange(availableGit.FindAll(a => Blocked(a) == null && a.Latest != null));
                }
            }
            if (due.Count == 0) return false;
            if (Game.Running(game))
            {
                foreach (TrackedAddon a in due) if (!waiting.Contains(a)) waiting.Add(a);
                closedSince = DateTime.MinValue;
                watch.Start();
                Status(due.Count == 1 ? due[0].Name + " " + due[0].Known + " waits for WoW Forever to close." : due.Count + " updates wait for WoW Forever to close.", CGold);
                list.Invalidate();
                return false;
            }
            RunQueue(due, true);
            return true;
        }

        void WatchGame()
        {
            if (waiting.Count == 0) { watch.Stop(); return; }
            if (Game.Running(game)) { closedSince = DateTime.MinValue; return; }
            if (closedSince == DateTime.MinValue) { closedSince = DateTime.Now; return; }
            if ((DateTime.Now - closedSince).TotalSeconds < 8 || busy) return;
            watch.Stop();
            List<TrackedAddon> due = new List<TrackedAddon>(waiting);
            waiting.Clear();
            RunQueue(due, true);
        }

        void RunQueue(List<TrackedAddon> queue, bool quiet)
        {
            if (queue.Count == 0) { ShotIfAsked(); return; }
            TrackedAddon a = queue[0];
            queue.RemoveAt(0);
            Install(a, quiet, delegate { RunQueue(queue, quiet); });
        }

        bool Trust(TrackedAddon a)
        {
            if (a.Trusted) return true;
            string text = a.IsPack
                ? "Guides on polestar.guide are written by players. " + a.Name + " is by " + a.By + (a.Entry != null && a.Entry.Reviewed ? " and was reviewed by the site." : ", not reviewed by the site yet.") + "\n\n" +
                  "ForeverUI Manager takes it only as polestar.guide's signed list gives it, checked against its sha256, and only with the files Polestar's guide compiler makes (no settings, no other code).\n\n" +
                  "It needs Polestar, from the Addons tab."
                : a.Guide
                ? "Guides run inside WoW Forever with your character and account, and a guide from GitHub may carry code of its own.\n\n" +
                  "Install " + a.Repo + " only if you trust its author. It comes straight from its GitHub releases " +
                  "(github.com/" + a.Repo + "), checked against GitHub's sha256, and only as PolestarPack_ folders: no other addon comes with it." +
                  (a.Source == "search" ? "\n\nA GitHub search found it: it is not on ForeverUI Manager's list." : "") +
                  (a.Betas ? "\n\nIt comes as a test version (pre-release)." : "")
                : "Addons run inside WoW Forever with your character and account.\n\n" +
                  "Install " + a.Repo + " only if you trust its author. It comes straight from its GitHub releases " +
                  "(github.com/" + a.Repo + "), checked against GitHub's sha256, with nothing in between.\n\n" +
                  "Folders of the same names already in AddOns go to the Recycle Bin.";
            if (MessageBox.Show(this, text, "Install " + a.Name, MessageBoxButtons.OKCancel, MessageBoxIcon.Information) != DialogResult.OK) return false;
            a.Trusted = true;
            if (addons.Contains(a)) Store.Save(addons);
            return true;
        }

        bool GameOpenOk(string doing)
        {
            if (!Game.Running(game)) return true;
            return MessageBox.Show(this, "WoW Forever is open. " + doing + " now anyway?\n\nThe game reads the new files at your next /reload or login.",
                "WoW Forever is open", MessageBoxButtons.OKCancel, MessageBoxIcon.Warning) == DialogResult.OK;
        }

        // A guide that changed hands or folders since it went in: said, and only with a yes.
        bool PinsOk(TrackedAddon a)
        {
            if (!a.IsPack || a.Tag == null || a.Entry == null || SamePins(a)) return true;
            PackEntry e = a.Entry;
            string what = a.Uid != e.Uid ? "polestar.guide now has another guide under the id " + e.Id + " (the one you have was replaced)"
                : a.PublisherId != e.PublisherId ? "its publisher changed (now " + (e.PublisherHandle ?? "someone else") + ")"
                : "its folders changed (now " + string.Join(", ", e.Folders) + ")";
            return MessageBox.Show(this, a.Name + ": " + what + ".\n\nUpdate anyway?", "Update " + a.Name, MessageBoxButtons.OKCancel, MessageBoxIcon.Warning) == DialogResult.OK;
        }

        void InstallPicked()
        {
            TrackedAddon a = Picked();
            if (a == null || game == null) return;
            if (a.WithGuides)
            {
                string why = Blocked(a);
                if (why != null) { Status("Can't install " + a.Name + ": " + why.TrimEnd('.') + ".", CRed); return; }
            }
            if (!Trust(a) || !PinsOk(a) || !GameOpenOk(a.Tag == null ? "Install" : "Update")) return;
            Install(a, false, null);
        }

        // The ticked ones not installed yet, then the updates that wait.
        void UpdateAll()
        {
            List<TrackedAddon> fresh = ToInstall();
            List<TrackedAddon> due = new List<TrackedAddon>(fresh);
            due.AddRange(Rows().FindAll(a => a.UpdateWaits && !a.Missing && (!a.IsPack || (SamePins(a) && Blocked(a) == null))));
            if (due.Count == 0 || game == null) return;
            if (!TrustAll(fresh) || !GameOpenOk(fresh.Count > 0 ? "Install" : "Update")) return;
            RunQueue(due, false);
        }

        // One yes for all the new ones Install all puts in, with what they are and how big.
        bool TrustAll(List<TrackedAddon> fresh)
        {
            List<TrackedAddon> asked = fresh.FindAll(a => !a.Trusted);
            if (asked.Count == 0) return true;
            if (asked.Count == 1) return Trust(asked[0]);
            long total = 0;
            bool allSized = true;
            List<string> lines = new List<string>();
            foreach (TrackedAddon a in asked)
            {
                long size = a.Latest != null ? a.Latest.Size : -1;
                if (size > 0) total += size; else allSized = false;
                lines.Add("  " + a.Name + "  (github.com/" + a.Repo + (size > 0 ? ", " + Bytes(size) : "") + ")");
            }
            string text = "Install these " + asked.Count + " addons?\n\n" + string.Join("\n", lines.ToArray()) + "\n\n" +
                "Addons run inside WoW Forever with your character and account. Each comes straight from its author's GitHub releases, " +
                "checked against GitHub's sha256, with nothing in between. Folders of the same names already in AddOns go to the Recycle Bin." +
                (total > 0 ? "\n\nAbout " + Bytes(total) + (allSized ? "" : " or more") + " to download." : "");
            if (MessageBox.Show(this, text, "Install all", MessageBoxButtons.OKCancel, MessageBoxIcon.Information) != DialogResult.OK) return false;
            foreach (TrackedAddon a in asked) a.Trusted = true;
            Store.Save(addons);
            return true;
        }

        void Install(TrackedAddon a, bool quiet, Action then)
        {
            string addonsFolder = AddOns();
            Release known = a.Latest;
            string[] before = a.Folders;
            string label = a.RepoName + " " + (a.Tag ?? "by hand");
            PackEntry entry = a.Entry;
            Work("Getting " + a.Name + "...", delegate
            {
                Release r = a.IsPack ? entry.AsRelease() : known ?? GitHub.Latest(a);
                string temp = Path.Combine(Path.GetTempPath(), "ForeverUIManager");
                Directory.CreateDirectory(temp);
                Installer.CleanTemp(temp);
                // A GitHub download is taken up where it stopped, even at the
                // next try (a voice pack is 1.5 GB); a guide's comes whole.
                bool resume = r.Origin == null;
                string zip = resume ? Installer.PartPath(temp, r) : Path.Combine(temp, Guid.NewGuid().ToString("N").Substring(0, 8) + ".zip");
                bool keep = false, whole = false;
                try
                {
                    if (a.IsPack) Packs.CheckOwnership(addonsFolder, entry);
                    long have = resume && File.Exists(zip) ? new FileInfo(zip).Length : 0;
                    Installer.RoomToDownload(temp, addonsFolder, r.Size, have);
                    Say(a, "Downloading...", 0);
                    if (!(have > 0 && have == r.Size))
                        Net.Download(r.ZipUrl, zip, delegate(long done, long total)
                        {
                            long all = total > 0 ? total : r.Size;
                            float part = all > 0 ? (float)done / all : -1;
                            Say(a, all > 0 ? "Downloading " + (int)(part * 100) + "%" + (all >= 100L * 1048576 ? " of " + Bytes(all) : "") : "Downloading " + Bytes(done), part);
                        }, r.Origin, r.Cap, resume);
                    whole = true;
                    Say(a, "Checking...", 1);
                    Placed placed;
                    if (a.IsPack)
                    {
                        Say(a, "Installing...", 1);
                        placed = Packs.Install(addonsFolder, entry, zip, before);
                    }
                    else
                    {
                        Installer.Verify(zip, r);
                        if (a.Guide) Installer.OnlyGuides(zip);
                        Installer.RoomToUnpack(addonsFolder, zip);
                        // Checked whole: kept if it cannot go in now (a folder in use), not downloaded again.
                        keep = resume;
                        Say(a, "Installing...", 1);
                        placed = Installer.Put(addonsFolder, zip, before, label);
                    }
                    keep = false;
                    return new object[] { r, placed };
                }
                catch
                {
                    // Half a big download is kept for the next try.
                    if (resume && !whole && File.Exists(zip) && new FileInfo(zip).Length > 8L * 1048576) keep = true;
                    throw;
                }
                finally
                {
                    try { if (!keep && File.Exists(zip)) File.Delete(zip); } catch { }
                }
            }, delegate(object result)
            {
                object[] pair = (object[])result;
                Release r = (Release)pair[0];
                Placed placed = (Placed)pair[1];
                bool updated = a.Tag != null;
                a.Busy = null;
                a.Latest = r;
                a.Known = r.Tag;
                a.Tag = r.Tag;
                a.Asset = r.ZipName;
                a.Folders = placed.Folders;
                a.Want = true;
                a.InstalledAt = DateTime.Now.ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture);
                if (a.IsPack)
                {
                    a.Uid = entry.Uid;
                    a.PublisherId = entry.PublisherId;
                    a.PublisherHandle = entry.PublisherHandle;
                    a.Pulled = null;
                }
                // A zip of PolestarPack_ folders only is a guide, wherever it was added.
                if (!a.IsPack && placed.Folders.All(f => f.StartsWith("PolestarPack_", StringComparison.Ordinal))) a.Guide = true;
                if (!addons.Contains(a)) { addons.Add(a); available.Remove(a); availableGit.Remove(a); }
                Store.Save(addons);
                Fill();
                string said = a.Name + " " + r.Tag + (updated ? " is in: " : " installed: ") + placed.Folders.Length + " folder(s) in AddOns."
                    + (placed.Skipped > 0 ? " " + placed.Skipped + " file(s) that are not addon files were left out." : "")
                    + (placed.Left != null ? " The old copy could not go to the Recycle Bin; it is in " + placed.Left + "." : "")
                    + (r.Sha256 == null ? " (No sha256 from its source this time: only the download itself was checked.)" : "");
                Status(said, CGreen);
                Core.Log(said);
                if (quiet && !Visible) tray.ShowBalloonTip(5000, "ForeverUI Manager", a.Name + " " + r.Tag + (updated ? " is in." : " installed."), ToolTipIcon.Info);
                if (then != null) then();
            }, delegate(Exception why)
            {
                a.Busy = null;
                Status("Could not install " + a.Name + ": " + why.Message, CRed);
                Core.Log("install " + a.Repo + ": " + why);
                list.Invalidate();
                if (then != null) then();
            });
        }

        void UninstallPicked()
        {
            TrackedAddon a = Picked();
            if (a == null || a.Tag == null || game == null) return;
            if (MessageBox.Show(this, "Move " + a.Name + "'s " + a.Folders.Length + " folder(s) from AddOns to the Recycle Bin?\n\nIts settings (in WTF) stay, for when you install it again.",
                "Uninstall " + a.Name, MessageBoxButtons.OKCancel, MessageBoxIcon.Question) != DialogResult.OK) return;
            if (!GameOpenOk("Uninstall")) return;
            string addonsFolder = AddOns();
            string[] folders = a.Folders;
            string label = a.RepoName + " " + a.Tag;
            Work("Uninstalling " + a.Name + "...", delegate { return Installer.Remove(addonsFolder, folders, label); }, delegate(object result)
            {
                string left = result as string;
                a.Tag = null;
                a.Folders = null;
                a.Asset = null;
                a.InstalledAt = null;
                // No longer ticked: Install all leaves it out (a required one stays ticked).
                a.Want = a.Required;
                // Back among the ones offered: polestar.guide's guides, ours and the found ones.
                if (a.IsPack || (a.Source != null && a.Source != "pack"))
                {
                    addons.Remove(a);
                    if (!a.IsPack) gitGuides[a.Repo] = a;
                }
                Store.Save(addons);
                Available();
                Fill();
                Status(left == null ? a.Name + " uninstalled: its folders are in the Recycle Bin." : a.Name + " uninstalled; the Recycle Bin refused its folders, which are in " + left + ".", CGreen);
                Core.Log("uninstalled " + a.Repo + (left != null ? ", left in " + left : ""));
            }, null);
        }

        void RemovePicked()
        {
            TrackedAddon a = Picked();
            if (a == null || a.IsPack) return;
            string text = a.Tag != null
                ? "Take " + a.Name + " off the list?\n\nIts folders stay in AddOns and it stops being updated. (Uninstall removes the folders.)"
                : "Take " + a.Name + " off the list?";
            if (a.Source == "pack") text += "\n\nIt came with the ForeverUI pack: it does not come back by itself. To keep it on the list without installing it, untick it instead.";
            if (MessageBox.Show(this, text, "Remove " + a.Name, MessageBoxButtons.OKCancel, MessageBoxIcon.Question) != DialogResult.OK) return;
            addons.Remove(a);
            waiting.Remove(a);
            Store.Save(addons);
            Fill();
            Status(a.Name + " is off the list." + (a.Source == "pack" ? " It came with the ForeverUI pack and does not come back by itself." : ""));
        }

        void AddFromGitHub()
        {
            string given = AskRepo();
            if (given == null) return;
            string repo = GitHub.ParseRepo(given);
            if (repo == null) { Status("That is not a GitHub link (github.com/owner/name).", CRed); return; }
            TrackedAddon same = addons.Find(a => string.Equals(a.Repo, repo, StringComparison.OrdinalIgnoreCase));
            TrackedAddon offered;
            if (same == null && gitGuides.TryGetValue(repo, out offered)) same = offered;
            if (same != null)
            {
                SwitchTab(same.WithGuides);
                Pick(same);
                Status(same.Name + " is on the list already.");
                return;
            }
            AddRepo(TrackedAddon.ForRepo(repo));
        }

        void AddRepo(TrackedAddon fresh)
        {
            string repo = fresh.Repo;
            Work("Looking up " + repo + " on GitHub...", delegate { return GitHub.Latest(fresh); }, delegate(object result)
            {
                Release r = (Release)result;
                fresh.Latest = r;
                fresh.Known = r.Tag;
                if (r.ZipName != null && r.ZipName.StartsWith("PolestarPack_", StringComparison.OrdinalIgnoreCase)) fresh.Guide = true;
                addons.Add(fresh);
                Store.Save(addons);
                SwitchTab(fresh.Guide);
                Fill();
                Pick(fresh);
                Status(fresh.Name + " " + r.Tag + (r.Test ? " (a test version)" : "") + " is on the list" + (fresh.Guide ? ", with the Polestar guides" : "") + ". Install puts it in AddOns.", CGreen);
            }, delegate(Exception why)
            {
                // Only test versions: taken only with a yes.
                if (why is Final && why.Message == GitHub.NoStable && !fresh.Betas)
                {
                    if (MessageBox.Show(this, repo + " has only test versions (pre-releases) on GitHub.\n\nAdd it with its test versions?", "Add " + fresh.Name,
                        MessageBoxButtons.OKCancel, MessageBoxIcon.Question) == DialogResult.OK)
                    {
                        fresh.Betas = true;
                        AddRepo(fresh);
                    }
                    else Status("Not added: " + why.Message + ".", CDim);
                    return;
                }
                if (why is Final) { Status("Not added: " + why.Message + ".", CRed); return; }
                // GitHub out for now: on the list all the same, checked again later.
                fresh.Problem = why.Message;
                addons.Add(fresh);
                Store.Save(addons);
                Fill();
                Pick(fresh);
                Status(repo + " is on the list, but GitHub did not answer: " + why.Message + ".", CGold);
            });
        }

        // Polestar guides on GitHub that are not on the list: GitHub's search
        // for "polestar forever", then each new repository's newest release
        // (one call each, ten at most), kept when its zip is a PolestarPack_.
        void FindOnGitHub()
        {
            if (busy) return;
            HashSet<string> seen = new HashSet<string>(addons.Select(a => a.Repo).Concat(gitGuides.Keys), StringComparer.OrdinalIgnoreCase);
            seen.Add("fitzforge/polestar");
            List<TrackedAddon> found = new List<TrackedAddon>();
            int looked = 0;
            Work("Searching GitHub for Polestar guides...", delegate
            {
                List<string> repos = GitHub.Search("polestar forever").Where(r => !seen.Contains(r)).Take(10).ToList();
                foreach (string repo in repos)
                {
                    looked++;
                    TrackedAddon g = new TrackedAddon { Repo = repo, Guide = true, Source = "search" };
                    try { g.Latest = GitHub.Latest(g); }
                    catch (Final why)
                    {
                        if (why.Message != GitHub.NoStable) continue;
                        g.Betas = true;
                        try { g.Latest = GitHub.Latest(g); } catch (Exception) { continue; }
                    }
                    catch (Exception) { continue; }
                    if (g.Latest.ZipName == null || !g.Latest.ZipName.StartsWith("PolestarPack_", StringComparison.OrdinalIgnoreCase)) continue;
                    g.Known = g.Latest.Tag;
                    g.Title = Regex.Replace(Path.GetFileNameWithoutExtension(g.Latest.ZipName), @"^PolestarPack_|-[vV]?\d[\d.]*$", "");
                    found.Add(g);
                }
                return null;
            }, delegate
            {
                foreach (TrackedAddon g in found) gitGuides[g.Repo] = g;
                guidesAt = DateTime.Now;
                Available();
                SwitchTab(true);
                Fill();
                if (found.Count > 0) Pick(found[0]);
                Status(found.Count > 0
                    ? "Found " + found.Count + " guide(s) on GitHub that are not on the list: " + string.Join(", ", found.Select(g => g.Repo).ToArray()) + "."
                    : "No new Polestar guides on GitHub (" + looked + " other repositories looked at).", found.Count > 0 ? CGreen : CDim);
                Core.Log("search: " + looked + " looked at, " + found.Count + " found" + (found.Count > 0 ? ": " + string.Join(", ", found.Select(g => g.Repo).ToArray()) : ""));
                ShotIfAsked();
            }, delegate(Exception why)
            {
                Status("GitHub's search did not answer: " + why.Message + ".", CRed);
                Core.Log("search: " + why.Message);
                ShotIfAsked();
            });
        }

        string AskRepo()
        {
            using (Form ask = new Form())
            {
                ask.Text = "Add from GitHub";
                ask.FormBorderStyle = FormBorderStyle.FixedDialog;
                ask.StartPosition = FormStartPosition.CenterParent;
                ask.MinimizeBox = ask.MaximizeBox = false;
                ask.ShowInTaskbar = false;
                ask.BackColor = CBack;
                ask.ForeColor = CText;
                ask.Font = Font;
                ask.AutoScaleMode = AutoScaleMode.None;
                ask.ClientSize = new Size(S(480), S(150));
                Label say = new Label { Text = "The addon's GitHub link (github.com/owner/name) or owner/name:", AutoSize = true, Location = new Point(S(16), S(16)) };
                ask.Controls.Add(say);
                TextBox box = new TextBox { Location = new Point(S(16), S(44)), Size = new Size(S(448), S(24)), BackColor = CPanel, ForeColor = CText, BorderStyle = BorderStyle.FixedSingle };
                try
                {
                    string clip = Clipboard.ContainsText() ? Clipboard.GetText().Trim() : "";
                    if (clip.Length < 300 && GitHub.ParseRepo(clip) != null) box.Text = clip;
                }
                catch { }
                ask.Controls.Add(box);
                Label note = new Label { Text = "It is checked against its own releases on GitHub: nothing in between.", AutoSize = true, Font = small, ForeColor = CDim, Location = new Point(S(16), S(74)) };
                ask.Controls.Add(note);
                Button ok = new Button(), cancel = new Button();
                Style(ok, "Add", 254, 106, 100, ask);
                Style(cancel, "Cancel", 364, 106, 100, ask);
                ok.DialogResult = DialogResult.OK;
                cancel.DialogResult = DialogResult.Cancel;
                ask.AcceptButton = ok;
                ask.CancelButton = cancel;
                ask.HandleCreated += delegate { int dark = 1; try { Native.DwmSetWindowAttribute(ask.Handle, 20, ref dark, 4); } catch { } };
                return ask.ShowDialog(this) == DialogResult.OK && box.Text.Trim() != "" ? box.Text.Trim() : null;
            }
        }

        void PickGame()
        {
            using (FolderBrowserDialog pick = new FolderBrowserDialog())
            {
                pick.Description = "Pick WoW Forever's folder (_forever_, the one with Wow.exe), or World of Warcraft's folder.";
                if (game != null) pick.SelectedPath = game;
                if (pick.ShowDialog(this) != DialogResult.OK) return;
                string chosen = pick.SelectedPath;
                if (Game.IsForever(Path.Combine(chosen, "_forever_"))) chosen = Path.Combine(chosen, "_forever_");
                if (!Game.IsForever(chosen)) { Status("That is not WoW Forever's folder: no Wow.exe of WoW Forever in " + chosen + ".", CRed); return; }
                Core.SetSetting("game", chosen);
                game = chosen;
                ShowGame();
                Fill();
                Status("WoW Forever is in " + chosen + ".");
            }
        }

        void SetUpTray()
        {
            tray.Icon = AppIcon();
            tray.Text = "ForeverUI Manager";
            ContextMenuStrip menu = new ContextMenuStrip();
            menu.Items.Add("Open", null, delegate { ShowMe(); });
            menu.Items.Add("Check for updates", null, delegate { CheckAll(true); });
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Exit", null, delegate { quitting = true; Close(); });
            tray.ContextMenuStrip = menu;
            tray.MouseClick += delegate(object sender, MouseEventArgs e) { if (e.Button == MouseButtons.Left) ShowMe(); };
            tray.BalloonTipClicked += delegate { ShowMe(); };
            tray.Visible = !shotMode;
        }

        // Tests (FUM_SHOT=<png>): the window drawn into a file once the work
        // is done, then closed.
        void ShotIfAsked()
        {
            string path = Core.Env("FUM_SHOT");
            if (path == "" || shotTaken) return;
            shotTaken = true;
            // FUM_SHOT_PICK: the row of that name picked and in view.
            ListViewItem pick = list.Items.Cast<ListViewItem>().FirstOrDefault(i => ((TrackedAddon)i.Tag).Name == Core.Env("FUM_SHOT_PICK"));
            if (pick != null) { pick.Selected = true; pick.EnsureVisible(); }
            System.Windows.Forms.Timer later = new System.Windows.Forms.Timer { Interval = 800 };
            later.Tick += delegate
            {
                later.Stop();
                // Drawn straight into the picture: off screen, Windows never
                // composes some of it, so a print of the screen comes out white.
                using (Bitmap picture = new Bitmap(ClientSize.Width, ClientSize.Height))
                {
                    using (Bitmap whole = new Bitmap(Width, Height))
                    {
                        DrawToBitmap(whole, new Rectangle(0, 0, Width, Height));
                        Point corner = PointToScreen(Point.Empty);
                        using (Graphics g = Graphics.FromImage(picture))
                            g.DrawImage(whole, -(corner.X - Left), -(corner.Y - Top));
                    }
                    picture.Save(path, ImageFormat.Png);
                }
                quitting = true;
                Close();
            };
            later.Start();
        }
    }
}
