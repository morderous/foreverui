// Checks for ForeverUI Manager, compiled with the app (/main:ForeverUIManager.Tests).
//   Tests.exe                    offline checks only
//   Tests.exe live               also asks GitHub (about 4 API calls, then its pages) and polestar.guide
//   Tests.exe zip <file.zip> <n> also installs a real release zip into a test AddOns (n folders expected)
//   Tests.exe index <dir>        also checks an index.json and index.json.sig downloaded from polestar.guide
// Everything happens in a folder under %TEMP%; the real AddOns, settings and
// Run key are never touched (FUM_HOME and FUM_TEST_BIN are set first).
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;

namespace ForeverUIManager
{
    static class Tests
    {
        static int passed, failed;
        static string root;

        static void Is(bool ok, string what)
        {
            if (ok) passed++;
            else { failed++; Console.WriteLine("FAIL " + what); }
        }

        static bool Throws(Action act, string containing)
        {
            try { act(); return false; }
            catch (Exception why)
            {
                if (containing != null && !why.Message.Contains(containing)) { Console.WriteLine("  (said: " + why.Message + ")"); return false; }
                return true;
            }
        }

        static int Main(string[] args)
        {
            root = Path.Combine(Path.GetTempPath(), "fum-tests-" + Guid.NewGuid().ToString("N").Substring(0, 6));
            Directory.CreateDirectory(root);
            Environment.SetEnvironmentVariable("FUM_HOME", Path.Combine(root, "home"));
            Environment.SetEnvironmentVariable("FUM_TEST_BIN", Path.Combine(root, "bin"));
            try
            {
                Repos();
                Folders();
                ReleaseJson();
                Zips();
                PutAndUpdate();
                RollBack();
                Store();
                Signatures();
                PackRules();
                PackInstall();
                GitGuides();
                PackList();
                Series();
                WebPages();
                Resume();
                Room();
                if (args.Length > 1 && args[0] == "guides") RealGuides(args[1]);
                if (args.Length > 0 && args[0] == "live") Live();
                if (args.Length > 2 && args[0] == "zip") RealZip(args[1], int.Parse(args[2]));
                if (args.Length > 1 && args[0] == "index") RealIndex(args[1]);
                if (args.Length > 1 && args[0] == "release") OurRelease(args[1]);
            }
            catch (Exception why)
            {
                failed++;
                Console.WriteLine("CRASH " + why);
            }
            finally
            {
                try { Directory.Delete(root, true); } catch { }
            }
            Console.WriteLine(passed + " ok, " + failed + " failed");
            return failed;
        }

        static void Repos()
        {
            Is(GitHub.ParseRepo("https://github.com/EllesmereGaming/EllesmereUI") == "EllesmereGaming/EllesmereUI", "link");
            Is(GitHub.ParseRepo("github.com/EllesmereGaming/EllesmereUI/releases/tag/v9.7.3") == "EllesmereGaming/EllesmereUI", "link with a path");
            Is(GitHub.ParseRepo("https://github.com/a-b/c.d.git") == "a-b/c.d", ".git");
            Is(GitHub.ParseRepo("git@github.com:owner/name") == "owner/name", "ssh");
            Is(GitHub.ParseRepo("owner/name") == "owner/name", "owner/name");
            Is(GitHub.ParseRepo("https://gitlab.com/owner/name") == null, "not GitHub");
            Is(GitHub.ParseRepo("hello") == null, "not a link");
            Is(GitHub.ParseRepo("owner/..") == null, "dots");
            Is(GitHub.Digest("sha256:AEBFA8A60EE1185760D5C4E779C1DCEB999E1897295D0CDBA90DC740242FFDF2") == "aebfa8a60ee1185760d5c4e779c1dceb999e1897295d0cdba90dc740242ffdf2", "digest");
            Is(GitHub.Digest("md5:12") == null, "other digest");
            TrackedAddon polestar = TrackedAddon.ForRepo("https://github.com/fitzforge/polestar".Replace("https://github.com/", ""));
            Is(polestar.Title == "Polestar" && polestar.Series == @"^v\d" && polestar.ZipPattern == "Polestar-*.zip", "Polestar known");
            Is(Core.CompareVersions("0.3.1", "0.2.5") > 0 && Core.CompareVersions("0.3.0", "0.3.0") == 0 && Core.CompareVersions("v0.10", "0.9.9") > 0 && Core.CompareVersions("0.2", "0.2.1") < 0, "versions");
        }

        static string Folders(params string[] names)
        {
            return string.Join(",", Installer.FoldersIn(names).Select(f => f.Key + "=" + f.Value).ToArray());
        }

        static void Folders()
        {
            Is(Folders("EllesmereUI/EllesmereUI.toc", "EllesmereUI/Libs/LibStub/LibStub.toc", "EllesmereUI/core.lua",
                "EllesmereUIForeverEssentials/EllesmereUIForeverEssentials_Camelot.toc", "X/X-Mainline.toc")
                == "X/=X,EllesmereUI/=EllesmereUI,EllesmereUIForeverEssentials/=EllesmereUIForeverEssentials", "release layout, tagged .toc, libs inside");
            Is(Folders("Repo-main/Addon/Addon.toc", "Repo-main/README.md") == "Repo-main/Addon/=Addon", "a repository's archive");
            Is(Folders("Repo-main/MyAddon_Camelot.toc", "Repo-main/core.lua") == "Repo-main/=MyAddon", ".toc at the top of the archive");
            Is(Folders("MyAddon.toc", "core.lua") == "=MyAddon", ".toc at the top of the zip");
            Is(Folders("Docs/readme.md", "src/a.lua") == "", "no .toc");
            Is(Folders("A/A.toc", "A/B/B.toc", "C/C.toc") == "A/=A,C/=C", "nested addon stays inside");
            Is(!Installer.SafeFolder("Blizzard_AuctionUI") && !Installer.SafeFolder("..") && !Installer.SafeFolder("a\\b") && Installer.SafeFolder("EllesmereUI"), "safe folders");
            Is(Installer.ForeverInterface("120000, 120001, 16001") == "16001" && Installer.ForeverInterface("11507") == null, "Forever interface");
        }

        static void ReleaseJson()
        {
            string ellesmere = "{\"releases\":[{\"name\":\"EllesmereUI\",\"version\":\"v9.7.3\",\"filename\":\"EllesmereUI-v9.7.3.zip\",\"nolib\":false,\"metadata\":[{\"flavor\":\"mainline\",\"interface\":120000},{\"flavor\":\"forever\",\"interface\":16001}]}]}";
            Is(GitHub.ForeverIn(ellesmere) == "EllesmereUI-v9.7.3.zip", "release.json with forever");
            string mainline = "{\"releases\":[{\"filename\":\"A.zip\",\"nolib\":false,\"metadata\":[{\"flavor\":\"mainline\",\"interface\":120000}]}]}";
            Is(GitHub.ForeverIn(mainline) == null, "release.json without forever");
            string several = "{\"releases\":[{\"filename\":\"A-nolib.zip\",\"nolib\":true,\"metadata\":[{\"flavor\":\"forever\",\"interface\":16001}]},"
                + "{\"filename\":\"A-classic.zip\",\"nolib\":false,\"metadata\":[{\"flavor\":\"classic\",\"interface\":11507}]},"
                + "{\"filename\":\"A.zip\",\"nolib\":false,\"metadata\":[{\"flavor\":\"mainline\",\"interface\":120000},{\"interface\":16001}]}]}";
            Is(GitHub.ForeverIn(several) == "A.zip", "full zip before nolib, Interface alone");
            Is(GitHub.ForeverIn("{\"releases\":[{\"filename\":\"../x.zip\",\"metadata\":[{\"flavor\":\"forever\"}]}]}") == null, "path in filename refused");
        }

        static void Zips()
        {
            List<string> polestar = new List<string> { "Polestar-0.3.1.zip", "Polestar_Recorder-0.3.1.zip" };
            Is(GitHub.ZipByName(polestar, "polestar") == "Polestar-0.3.1.zip", "Polestar's zip by the repository's name");
            Is(GitHub.Like("Polestar-0.3.1.zip", "Polestar-*.zip") && !GitHub.Like("Polestar_Recorder-0.3.1.zip", "Polestar-*.zip"), "zip pattern");
            Is(GitHub.ZipByName(new List<string> { "A-classic.zip", "A-1.0.zip" }, "Other") == "A-1.0.zip", "the zip not named for another game");
            Is(GitHub.ZipByName(new List<string> { "x.zip", "y.zip" }, "Other") == null, "two zips, no way to tell");
            Dictionary<string, string> sums = GitHub.ParseSums("463c0fb15b7ec69cf38637d8dd60570d6c2a8b6253696f0177ae33e3519d599d  Polestar-0.3.1.zip\n3c6027e6dbb3c64f77185fa8c8c0ce89b19699a3cad8964a6cff6ec37f911d8c *Polestar_Recorder-0.3.1.zip\r\n");
            Is(sums.Count == 2 && sums["Polestar-0.3.1.zip"].StartsWith("463c0f") && sums["Polestar_Recorder-0.3.1.zip"].StartsWith("3c6027"), "SHA256SUMS read");
            Release r = new Release { Tag = "v0.3.1" };
            List<Asset> assets = new List<Asset> { new Asset { Name = "Polestar-0.3.1.zip", Url = "u1" }, new Asset { Name = "Polestar_Recorder-0.3.1.zip", Url = "u2" } };
            GitHub.PickZip(r, assets, "Polestar-*.zip", "polestar");
            Is(r.ZipUrl == "u1", "PickZip by pattern");
            Is(Throws(delegate { GitHub.PickZip(new Release(), assets, "Nope-*.zip", "polestar"); }, "no zip named like"), "PickZip with no match says so");
        }

        static string MakeZip(string name, Dictionary<string, string> files)
        {
            string path = Path.Combine(root, name);
            if (File.Exists(path)) File.Delete(path);
            using (ZipArchive zip = ZipFile.Open(path, ZipArchiveMode.Create))
                foreach (KeyValuePair<string, string> f in files)
                {
                    ZipArchiveEntry entry = zip.CreateEntry(f.Key);
                    if (f.Value == null) continue;
                    using (StreamWriter w = new StreamWriter(entry.Open(), new UTF8Encoding(false))) w.Write(f.Value);
                }
            return path;
        }

        static void PutAndUpdate()
        {
            string addons = Path.Combine(root, "game", "Interface", "AddOns");
            Directory.CreateDirectory(Path.Combine(addons, "Keep"));
            File.WriteAllText(Path.Combine(addons, "Keep", "Keep.toc"), "## Title: by hand");
            Directory.CreateDirectory(Path.Combine(addons, "Old"));
            File.WriteAllText(Path.Combine(addons, "Old", "Old.toc"), "## Title: old");

            string v1 = MakeZip("v1.zip", new Dictionary<string, string>
            {
                { "A/A.toc", "## Interface: 16001\n## Title: |cff00ff00A|r\n## Version: 1" },
                { "A/a.lua", "v1" },
                { "A/evil.exe", "MZ" },
                { "A/../../escape.lua", "out" },
                { "B/B_Camelot.toc", "## Interface: 16001" },
            });
            Placed first = Installer.Put(addons, v1, new[] { "Old" }, "Test v0");
            Is(first.Folders.Length == 2 && Directory.Exists(Path.Combine(addons, "A")) && Directory.Exists(Path.Combine(addons, "B")), "v1 in");
            Is(!Directory.Exists(Path.Combine(addons, "Old")), "the old version's leftover folder out");
            Is(Directory.Exists(Path.Combine(addons, "Keep")), "an addon put in by hand stays");
            Is(!File.Exists(Path.Combine(addons, "A", "evil.exe")) && first.Skipped == 2, "exe and path escape left out (" + first.Skipped + ")");
            Is(!File.Exists(Path.Combine(root, "game", "Interface", "escape.lua")) && !File.Exists(Path.Combine(root, "game", "escape.lua")), "nothing outside its folder");
            Toc toc = Installer.ReadToc(Path.Combine(addons, "A"));
            Is(toc != null && toc.Title == "A" && toc.Version == "1" && toc.Interface == "16001", "toc read, colours off");
            Is(Installer.ReadToc(Path.Combine(addons, "B")) != null, "tagged toc read");
            Is(Directory.GetDirectories(Path.Combine(root, "bin")).Length == 1, "old folders to the bin together");
            Is(Directory.GetDirectories(Path.Combine(root, "game", "Interface")).Length == 1, "no staging left beside AddOns");

            string v2 = MakeZip("v2.zip", new Dictionary<string, string>
            {
                { "A/A.toc", "## Interface: 16001\n## Version: 2" },
                { "A/a.lua", "v2" },
            });
            Placed second = Installer.Put(addons, v2, first.Folders, "Test v1");
            Is(second.Folders.Length == 1 && File.ReadAllText(Path.Combine(addons, "A", "a.lua")) == "v2", "v2 replaced v1");
            Is(!Directory.Exists(Path.Combine(addons, "B")), "a folder v2 dropped is gone");
            Is(Directory.Exists(Path.Combine(addons, "Keep")), "by hand still there");

            string left = Installer.Remove(addons, second.Folders, "Test v2");
            Is(left == null && !Directory.Exists(Path.Combine(addons, "A")) && Directory.Exists(Path.Combine(addons, "Keep")), "uninstall");
            Is(Directory.GetDirectories(Path.Combine(root, "bin")).Length == 3, "each step's old copy in the bin");
        }

        static void RollBack()
        {
            string addons = Path.Combine(root, "game2", "Interface", "AddOns");
            Directory.CreateDirectory(Path.Combine(addons, "A"));
            File.WriteAllText(Path.Combine(addons, "A", "A.toc"), "old");
            Directory.CreateDirectory(Path.Combine(addons, "Z"));
            File.WriteAllText(Path.Combine(addons, "Z", "Z.toc"), "old z");
            string zip = MakeZip("v3.zip", new Dictionary<string, string> { { "A/A.toc", "new" }, { "Z/Z.toc", "new z" } });
            bool threw = false;
            using (FileStream held = new FileStream(Path.Combine(addons, "Z", "Z.toc"), FileMode.Open, FileAccess.Read, FileShare.None))
            {
                try { Installer.Put(addons, zip, null, "Locked"); }
                catch (Exception why) { threw = why.Message.Contains("could not be moved"); }
            }
            Is(threw, "a file in use stops it");
            Is(File.ReadAllText(Path.Combine(addons, "A", "A.toc")) == "old" && File.ReadAllText(Path.Combine(addons, "Z", "Z.toc")) == "old z", "everything put back as it was");
            Is(Directory.GetDirectories(Path.Combine(root, "game2", "Interface")).Length == 1, "no staging left after a roll back");
        }

        static void Store()
        {
            List<TrackedAddon> list = ForeverUIManager.Store.Load();
            Is(list.Count == 2 && list[0].Repo == "EllesmereGaming/EllesmereUI" && list[1].Repo == "fitzforge/polestar" && list[1].ZipPattern == "Polestar-*.zip", "a new list starts with EllesmereUI and Polestar");
            list[0].Tag = "v1";
            list[0].Folders = new[] { "A", "B" };
            list[0].Auto = false;
            list[0].Trusted = true;
            list.RemoveAt(1);
            TrackedAddon pack = new TrackedAddon { Kind = "pack", Repo = "pack:lightforge", PackId = "lightforge", Tag = "1.0.0", Folders = new[] { "PolestarPack_lightforge" }, Uid = "u-1", PublisherId = "p-1", Auto = false, Title = "Lightforge" };
            list.Add(pack);
            ForeverUIManager.Store.Save(list);
            List<TrackedAddon> again = ForeverUIManager.Store.Load();
            Is(again.Count == 2 && again[0].Tag == "v1" && again[0].Folders.Length == 2 && !again[0].Auto && again[0].Trusted, "the list kept");
            Is(again.Count == 2 && again[1].IsPack && again[1].PackId == "lightforge" && again[1].Uid == "u-1" && again[1].Tag == "1.0.0" && !again[1].Auto, "a guide kept with its pins");
            Is(!again.Exists(a => a.Repo == "fitzforge/polestar"), "a starter taken off stays off");
        }

        static byte[] Hex(string hex)
        {
            byte[] bytes = new byte[hex.Length / 2];
            for (int i = 0; i < bytes.Length; i++) bytes[i] = Convert.ToByte(hex.Substring(i * 2, 2), 16);
            return bytes;
        }

        static void Signatures()
        {
            // RFC 8032, 7.1, tests 1 to 3.
            Is(Ed25519.Verify(Hex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"), new byte[0],
                Hex("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b")), "RFC 8032 test 1");
            Is(Ed25519.Verify(Hex("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"), Hex("72"),
                Hex("92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00")), "RFC 8032 test 2");
            Is(Ed25519.Verify(Hex("fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025"), Hex("af82"),
                Hex("6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a")), "RFC 8032 test 3");
            Is(!Ed25519.Verify(Hex("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"), Hex("73"),
                Hex("92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00")), "another message fails");
            Is(!Ed25519.Verify(Hex("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"), Hex("72"),
                Hex("92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c01")), "another signature fails");
            Is(Packs.Snapshot("\"43-1793826586433\"") == "43" && Packs.Snapshot("W/\"6-1\"") == "6" && Packs.Snapshot("\"abc\"") == null, "snapshot id from the ETag");
        }

        static PackEntry Ember()
        {
            return new PackEntry { Id = "emberway", Version = "1.0.0", Title = "Emberway", Author = "x", Folders = new[] { "PolestarPack_emberway", "PolestarPack_emberway_deDE" } };
        }

        const string MainToc = "## Interface: 16001\n## Title: Polestar Community: Emberway\n## X-Polestar-Pack: emberway\n## Dependencies: Polestar\n# generated\nPack.lua\nGuides.lua\n";
        const string TextsToc = "## Interface: 16001\n## Title-deDE: Emberway\n## X-Polestar-Texts: emberway\n## LoadOnDemand: 1\nTexts.lua\n";

        static Dictionary<string, string> GoodPack()
        {
            return new Dictionary<string, string>
            {
                { "PolestarPack_emberway/", null },
                { "PolestarPack_emberway/PolestarPack_emberway.toc", MainToc },
                { "PolestarPack_emberway/Pack.lua", "-- pack" },
                { "PolestarPack_emberway/Guides.lua", "-- guides" },
                { "PolestarPack_emberway/LICENSE-DATA.txt", "data" },
                { "PolestarPack_emberway/Images/map.tga", "tga" },
                { "PolestarPack_emberway_deDE/PolestarPack_emberway_deDE.toc", TextsToc },
                { "PolestarPack_emberway_deDE/Texts.lua", "-- texts" },
            };
        }

        static bool Refused(string name, Action<Dictionary<string, string>> change, string containing)
        {
            Dictionary<string, string> files = GoodPack();
            change(files);
            string zip = MakeZip(name + ".zip", files);
            return Throws(delegate { Packs.CheckZip(zip, Ember()); }, containing);
        }

        static void PackRules()
        {
            Is(Packs.CheckToc(MainToc, false).SequenceEqual(new[] { "Pack.lua", "Guides.lua" }), "a guide's .toc read");
            Is(Throws(delegate { Packs.CheckToc(MainToc + "## SavedVariables: X\n", false); }, "directive"), "SavedVariables refused");
            Is(Throws(delegate { Packs.CheckToc(MainToc + "Other.lua\n", false); }, "loads a file"), "another Lua file refused");
            Is(Throws(delegate { Packs.CheckToc(TextsToc + "Pack.lua\n", true); }, "loads a file"), "a locale .toc loads only Texts.lua");

            string good = MakeZip("good.zip", GoodPack());
            Is(!Throws(delegate { Packs.CheckZip(good, Ember()); }, null), "a guide's zip as the compiler makes it");
            Is(Refused("xml", f => f["PolestarPack_emberway/Frames.xml"] = "<Ui/>", "may not hold"), ".xml refused");
            Is(Refused("png", f => f["PolestarPack_emberway/pic.png"] = "png", "may not hold"), ".png refused");
            Is(Refused("unlisted", f => f["PolestarPack_emberway/MapFrames.lua"] = "--", "does not load"), "a Lua file its .toc does not load");
            Is(Refused("deep", f => f["PolestarPack_emberway/sub/x.lua"] = "--", "may not hold"), "a Lua file in a subfolder");
            Is(Refused("owner", f => f["PolestarPack_emberway/PolestarPack_emberway.toc"] = MainToc.Replace("emberway\n## Dep", "other\n## Dep"), "does not say"), "a .toc naming another guide");
            Is(Refused("foreign", f => f["SomeAddon/SomeAddon.toc"] = "## Title: x", "not this guide's"), "a folder that is not the guide's");
            Is(Refused("root", f => f["loose.lua"] = "--", "outside its folders"), "a file outside the folders");
            Is(Refused("missing", f => { f.Remove("PolestarPack_emberway_deDE/PolestarPack_emberway_deDE.toc"); f.Remove("PolestarPack_emberway_deDE/Texts.lua"); }, "has no PolestarPack_emberway_deDE"), "a listed folder missing");
            Is(Refused("device", f => f["PolestarPack_emberway/COM1.lua"] = "--", "unsafe path"), "a device name");
            Is(Refused("stream", f => f["PolestarPack_emberway/a.lua:x"] = "--", "unsafe path"), "a stream name");

            PackIndex index = new PackIndex();
            index.Revoked.Add(new PackRevoke { Id = "emberway", Uid = "u1", Versions = new[] { "1.0.0" }, Reason = "bad", Remove = false });
            index.Revoked.Add(new PackRevoke { Id = "emberway", Uid = "u1", Versions = null, Reason = "worse", Remove = true });
            index.Revoked.Add(new PackRevoke { Id = "other", Uid = "u2", Versions = new[] { "2.0" }, Reason = "x", Remove = false });
            Is(index.Revocation("emberway", "u1", "1.0.0").Reason == "worse", "remove before disable");
            Is(index.Revocation("emberway", "u9", "1.0.0") == null, "another guide under the same id is not pulled");
            Is(index.Revocation("other", "u2", "2.0") != null && index.Revocation("other", "u2", "2.1") == null, "only the versions named");
        }

        static void PackInstall()
        {
            string addons = Path.Combine(root, "game3", "Interface", "AddOns");
            Directory.CreateDirectory(addons);
            string zip = MakeZip("pack.zip", GoodPack());
            PackEntry entry = Ember();
            entry.Size = new FileInfo(zip).Length;
            entry.Sha256 = Core.Sha256Of(zip);
            Placed placed = Packs.Install(addons, entry, zip, null);
            Is(placed.Folders.Length == 2 && Packs.Owner(Path.Combine(addons, "PolestarPack_emberway")) == "emberway"
                && Packs.Owner(Path.Combine(addons, "PolestarPack_emberway_deDE")) == "emberway", "a guide installed, its folders its own");
            Is(Packs.InAddOns(addons, "emberway").Count == 2, "its folders found again");

            // An update without the locale folder takes the old one out.
            Dictionary<string, string> only = GoodPack();
            only.Remove("PolestarPack_emberway_deDE/PolestarPack_emberway_deDE.toc");
            only.Remove("PolestarPack_emberway_deDE/Texts.lua");
            string zip2 = MakeZip("pack2.zip", only);
            PackEntry newer = Ember();
            newer.Version = "1.1.0";
            newer.Folders = new[] { "PolestarPack_emberway" };
            newer.Size = new FileInfo(zip2).Length;
            newer.Sha256 = Core.Sha256Of(zip2);
            Placed second = Packs.Install(addons, newer, zip2, placed.Folders);
            Is(second.Folders.Length == 1 && !Directory.Exists(Path.Combine(addons, "PolestarPack_emberway_deDE")), "an older locale folder goes");

            PackEntry wrongSha = Ember();
            wrongSha.Size = new FileInfo(zip).Length;
            wrongSha.Sha256 = new string('0', 64);
            Is(Throws(delegate { Packs.Install(addons, wrongSha, zip, null); }, "sha256"), "a zip that is not the one the list names");

            // A folder of the guide's name that is not the guide's: never touched.
            string other = Path.Combine(root, "game4", "Interface", "AddOns");
            Directory.CreateDirectory(Path.Combine(other, "PolestarPack_emberway"));
            File.WriteAllText(Path.Combine(other, "PolestarPack_emberway", "PolestarPack_emberway.toc"), "## Title: mine");
            Is(Throws(delegate { Packs.Install(other, entry, zip, null); }, "in the way"), "a folder in the way stops it");
            Is(File.ReadAllText(Path.Combine(other, "PolestarPack_emberway", "PolestarPack_emberway.toc")) == "## Title: mine", "and stays as it was");
        }

        static void GitGuides()
        {
            TrackedAddon aurum = TrackedAddon.ForRepo("AurumTitanos/Aurums-Night-Elf-Druid-Guide");
            Is(aurum.Guide && aurum.Betas && aurum.Source == "list" && aurum.WithGuides, "Aurum's guide known, with test versions");
            TrackedAddon lodestar = TrackedAddon.ForRepo("petllama/lodestar-guides");
            Is(lodestar.Guide && !lodestar.Betas && lodestar.Title == "Lodestar Guides", "Lodestar's guides known");
            Is(!TrackedAddon.ForRepo("EllesmereGaming/EllesmereUI").Guide, "an addon is not a guide");

            string pure = MakeZip("gitpure.zip", new Dictionary<string, string>
            {
                { "PolestarPack_Lodestar/PolestarPack_Lodestar.toc", "## Interface: 16001\n## Title: Polestar Community: Lodestar\n## X-Polestar-Pack: lodestar\nPack.lua\nMapFrames.lua\nGuides.lua\n" },
                { "PolestarPack_Lodestar/Pack.lua", "--" }, { "PolestarPack_Lodestar/MapFrames.lua", "--" }, { "PolestarPack_Lodestar/Guides.lua", "--" },
                { "PolestarPack_Lodestar/LICENSE.txt", "MIT" },
            });
            Is(!Throws(delegate { Installer.OnlyGuides(pure); }, null), "a guide's zip from GitHub");
            string mixed = MakeZip("gitmixed.zip", new Dictionary<string, string>
            {
                { "PolestarPack_X/PolestarPack_X.toc", "## X-Polestar-Pack: x\nPack.lua\n" },
                { "OtherAddon/OtherAddon.toc", "## Title: other" },
            });
            Is(Throws(delegate { Installer.OnlyGuides(mixed); }, "more than a Polestar guide"), "a guide's zip that brings another addon is refused");

            string addons = Path.Combine(root, "game5", "Interface", "AddOns");
            Installer.Put(addons, pure, null, "pure");
            Is(Packs.Compiled(Path.Combine(addons, "PolestarPack_Lodestar")) == null, "only what the compiler makes");
            string code = MakeZip("gitcode.zip", new Dictionary<string, string>
            {
                { "PolestarPack_EveryQuest/PolestarPack_EveryQuest.toc", "## Interface: 16001\n## X-Polestar-Pack: every-quest\nPack.lua\nGuides.lua\n" },
                { "PolestarPack_EveryQuest/Pack.lua", "--" }, { "PolestarPack_EveryQuest/Guides.lua", "--" }, { "PolestarPack_EveryQuest/Core.lua", "--" },
            });
            Installer.Put(addons, code, null, "code");
            string said = Packs.Compiled(Path.Combine(addons, "PolestarPack_EveryQuest"));
            Is(said != null && said.Contains("Core.lua"), "code of its own said (" + said + ")");
            string listed = MakeZip("gitlisted.zip", new Dictionary<string, string>
            {
                { "PolestarPack_Planner/PolestarPack_Planner.toc", "## SavedVariables: PlannerDB\nCore.lua\n" },
                { "PolestarPack_Planner/Core.lua", "--" },
            });
            Installer.Put(addons, listed, null, "listed");
            said = Packs.Compiled(Path.Combine(addons, "PolestarPack_Planner"));
            Is(said != null && said.Contains("SavedVariables"), "a .toc beyond the compiler's said (" + said + ")");

            List<TrackedAddon> list = ForeverUIManager.Store.Load();
            TrackedAddon g = TrackedAddon.ForRepo("AurumTitanos/Aurums-Night-Elf-Druid-Guide");
            g.Tag = "v0.4.37";
            g.Folders = new[] { "PolestarPack_AurumForeverDruid" };
            TrackedAddon found = new TrackedAddon { Repo = "someone/some-guide", Guide = true, Source = "search", Tag = "v1", Folders = new[] { "PolestarPack_Some" } };
            list.Add(g);
            list.Add(found);
            ForeverUIManager.Store.Save(list);
            List<TrackedAddon> again = ForeverUIManager.Store.Load();
            TrackedAddon g2 = again.Find(a => a.Repo == g.Repo), f2 = again.Find(a => a.Repo == found.Repo);
            Is(g2 != null && g2.Guide && g2.Betas && g2.Source == "list" && g2.Tag == "v0.4.37", "a GitHub guide kept with its test versions");
            Is(f2 != null && f2.Guide && f2.Source == "search" && f2.Tag == "v1", "a found guide kept as found");
        }

        // The repository's own pack.json: tests/out/../../../pack.json.
        static string PackText()
        {
            string path = Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..", "..", "pack.json"));
            return File.ReadAllText(path, Encoding.UTF8);
        }

        static void FreshList()
        {
            string path = Path.Combine(Core.Home(), "addons.json");
            if (File.Exists(path)) File.Delete(path);
            Core.SetSetting("starters", null);
        }

        static void PackList()
        {
            string text = PackText();
            KnownRepo[][] read = Pack.Parse(text);
            KnownRepo[] items = read[0];
            Is(items.Length == 11 && read[1].Length == 4, "pack.json: 11 addons and 4 guides (" + items.Length + ", " + read[1].Length + ")");
            Is(items.Count(k => k.Required) == 4 && items.Where(k => k.Required).All(k => k.Ticked), "4 required, all ticked");
            KnownRepo[] voices = items.Where(k => !k.Ticked).ToArray();
            Is(voices.Length == 4 && voices.All(k => k.Repo == "rusty-key/spoken-wow" && k.Series != null && k.Zip != null), "the 4 voice packs come unticked, each with its series and zip");
            Is(items.Where(k => k.Repo == "rusty-key/spoken-wow").Select(k => k.Key).Distinct().Count() == 5, "Spoken and its voice packs: 5 keys from one repository");
            Is(items.All(k => k.Key.IndexOf(',') < 0) && items.Where(k => k.Series != null).All(k => k.Key.Split(' ').Length == 2), "a key has no comma, one space at most");
            Is(TrackedAddon.SameKey("Rusty-Key/Spoken-WoW " + Uri.EscapeDataString(@"^spoken/v\d"), TrackedAddon.KeyOf("rusty-key/spoken-wow", @"^spoken/v\d")), "the same key in another case");
            Is(!TrackedAddon.SameKey(TrackedAddon.KeyOf("a/b", @"^v\d"), TrackedAddon.KeyOf("a/b", @"^v\D")) && !TrackedAddon.SameKey("a/b", TrackedAddon.KeyOf("a/b", "x")), "another series is another key");

            Is(Throws(delegate { Pack.Parse("{\"format\":2,\"addons\":[{\"repo\":\"a/b\"}]}"); }, "format"), "a pack of another format is refused");
            Is(Throws(delegate { Pack.Parse("{\"format\":1,\"addons\":[{\"repo\":\"not a repo\"}]}"); }, "no addon"), "a pack with no addon is refused");
            KnownRepo[][] odd = Pack.Parse("{\"format\":1,\"addons\":[{\"repo\":\"a/b\",\"title\":\"A\\u0007B\"},{\"repo\":\"c/d\",\"series\":\"([\"},{\"repo\":\"e/f\",\"zip\":\"../x.zip\"},{\"repo\":\"a/b\"},{\"repo\":\"g/h\",\"ticked\":false,\"required\":true}]}");
            Is(odd[0].Length == 2 && odd[0][0].Title == "AB" && odd[0][1].Repo == "g/h" && odd[0][1].Ticked && odd[1].Length == 0,
                "bad entries left out, a twin once, a required one always ticked (" + odd[0].Length + ")");

            // A new list from the pack.
            FreshList();
            Pack.Use(text, true);
            Is(File.Exists(Path.Combine(Core.Home(), "pack.json")), "the pack read is kept for offline");
            List<TrackedAddon> list = ForeverUIManager.Store.Load();
            Is(list.Count == 11 && list.All(a => a.Source == "pack"), "a new list holds the pack's 11 addons (" + list.Count + ")");
            Is(list.Count(a => a.Required) == 4 && list.Find(a => a.Repo == "morderous/foreverui").Required, "ForeverUI and the other three are required");
            List<TrackedAddon> unticked = list.FindAll(a => !a.Want);
            Is(unticked.Count == 4 && unticked.All(a => a.Repo == "rusty-key/spoken-wow" && !a.Auto && a.Series.Contains("audio")), "the voice packs: unticked, no update by themselves");
            Is(list.FindAll(a => a.Want).All(a => a.Auto), "the ticked ones update by themselves");
            Is(list.Find(a => a.Title == "Spoken Quests Audio").ZipPattern == "SpokenQuestsAudioAll-*.zip", "a voice pack keeps its zip");

            // Taken off: an extra stays off, a required one comes back; a tick is kept.
            list.RemoveAll(a => a.Title == "Forever Quest Tint" || a.Title == "Polestar");
            list.Find(a => a.Title == "Spoken Bosses Audio").Want = true;
            ForeverUIManager.Store.Save(list);
            List<TrackedAddon> again = ForeverUIManager.Store.Load();
            Is(again.Count == 10 && !again.Exists(a => a.Title == "Forever Quest Tint"), "an extra taken off stays off");
            Is(again.Exists(a => a.Title == "Polestar" && a.Required && a.ZipPattern == "Polestar-*.zip"), "a required one comes back");
            Is(again.Find(a => a.Title == "Spoken Bosses Audio").Want && !again.Find(a => a.Title == "Spoken Places Audio").Want, "ticks kept");

            // The pack changes: a new extra joins, one gone from it stays on the list, no longer required.
            string changed = text.Replace("{ \"repo\": \"EllesmereGaming/EllesmereUI\", \"title\": \"EllesmereUI\", \"required\": true },", "")
                .Replace("{ \"repo\": \"Peterodox/YUI-Dialogue\", \"title\": \"Dialogue UI\" },",
                    "{ \"repo\": \"Peterodox/YUI-Dialogue\", \"title\": \"Dialogue UI\" },\n    { \"repo\": \"someone/new-addon\", \"title\": \"New Addon\" },");
            Is(changed != text && Pack.Use(changed, true), "a changed pack is taken");
            List<TrackedAddon> joined = ForeverUIManager.Store.Seed(again);
            Is(joined.Count == 1 && joined[0].Repo == "someone/new-addon" && joined[0].Want, "a new extra joins, ticked");
            TrackedAddon ell = again.Find(a => a.Repo == "EllesmereGaming/EllesmereUI");
            Is(ell != null && !ell.Required, "one the pack no longer has stays, not required");
            Is(ForeverUIManager.Store.Seed(again).Count == 0, "nothing joins twice");

            // From before the pack: Spoken added by hand (no series), Polestar a starter by its repository alone.
            FreshList();
            Core.SetSetting("starters", "EllesmereGaming/EllesmereUI,fitzforge/polestar");
            Core.WriteAll(Path.Combine(Core.Home(), "addons.json"), "{\"format\":1,\"addons\":[" +
                "{\"repo\":\"rusty-key/spoken-wow\",\"tag\":\"spoken/v3.8.3\",\"asset\":\"Spoken-3.8.3.zip\",\"folders\":[\"Spoken\",\"Spoken_Quests\"],\"title\":\"Spoken\",\"auto\":true,\"trusted\":true}," +
                "{\"repo\":\"fitzforge/polestar\",\"series\":\"^v\\\\d\",\"zip\":\"Polestar-*.zip\",\"tag\":\"v0.3.2\",\"folders\":[\"Polestar\"],\"auto\":true}]}");
            Pack.Use(text, true);
            List<TrackedAddon> old = ForeverUIManager.Store.Load();
            List<TrackedAddon> spoken = old.FindAll(a => a.Repo == "rusty-key/spoken-wow");
            TrackedAddon main = spoken.Find(a => a.Tag == "spoken/v3.8.3");
            Is(old.Count == 11 && spoken.Count == 5, "the old list joins the pack without twins (" + old.Count + ", " + spoken.Count + " Spoken)");
            Is(main != null && main.Series == @"^spoken/v\d" && main.ZipPattern == "Spoken-*.zip" && main.Want && main.Trusted, "Spoken added by hand takes the pack's series, kept installed");
            Is(old.Count(a => a.Repo == "fitzforge/polestar") == 1 && old.Find(a => a.Repo == "fitzforge/polestar").Tag == "v0.3.2", "Polestar once, as it was");
            Is(spoken.Count(a => a.Tag == null && !a.Want) == 4, "the voice packs join unticked");

            // Never read: the app's own two.
            Pack.Addons = null; Pack.Guides = null; Pack.Text = null;
            Is(KnownRepo.Addons().Length == 2 && KnownRepo.GuideRepos().Length == 5, "never read: the app's own lists");
            FreshList();
        }

        static string ReleaseJson(string tag, bool pre, params string[] assets)
        {
            List<object> list = new List<object>();
            foreach (string a in assets)
                list.Add(new Dictionary<string, object> { { "name", a }, { "browser_download_url", "https://github.com/x/y/releases/download/" + Uri.EscapeDataString(tag) + "/" + a }, { "size", 1234 }, { "digest", "sha256:" + new string('a', 64) } });
            return Json.Write(new Dictionary<string, object> { { "tag_name", tag }, { "prerelease", pre }, { "draft", false }, { "assets", list }, { "html_url", "https://github.com/x/y/releases/tag/" + tag } });
        }

        static void Series()
        {
            // Page 1: 100 releases of other things and the bosses pack; page 2: the quests pack.
            List<string> page1 = new List<string>();
            for (int i = 0; i < 99; i++) page1.Add(ReleaseJson("manager/v0.1." + i, false, "Spoken-Manager.exe"));
            page1.Insert(40, ReleaseJson("bosses-audio/v1.0.0", false, "SpokenBossesAudio-1.0.0.zip"));
            List<string> second = new List<string>();
            for (int i = 0; i < 98; i++) second.Add(ReleaseJson("launcher/v0.0." + i, false, "Spoken-Launcher.exe"));
            second.Insert(10, ReleaseJson("quests-audio/v2.6.0", true, "SpokenQuestsAudioAll-2.6.0.zip"));
            second.Insert(11, ReleaseJson("quests-audio/v2.5.0", false, "SpokenQuestsAudioAll-2.5.0.zip"));
            string page2 = "[" + string.Join(",", second.ToArray()) + "]";
            List<string> asked = new List<string>();
            GitHub.Forget();
            GitHub.FakeApi = delegate(string path)
            {
                asked.Add(path);
                if (path.Contains("page=2")) return page2;
                if (path.Contains("page=3")) return "[]";
                return "[" + string.Join(",", page1.ToArray()) + "]";
            };
            try
            {
                Release quests = GitHub.Latest("x/y", @"^quests-audio/v\d", "SpokenQuestsAudioAll-*.zip");
                Is(quests.Tag == "quests-audio/v2.5.0" && quests.ZipName == "SpokenQuestsAudioAll-2.5.0.zip" && quests.Sha256 == new string('a', 64) && quests.Size == 1234,
                    "a series found on the second page, its test version left out (" + quests.Tag + ")");
                Is(asked.Count == 2 && asked[0].Contains("per_page=100"), "two pages of 100 asked (" + string.Join(" ", asked.ToArray()) + ")");
                Release bosses = GitHub.Latest("x/y", @"^bosses-audio/v\d", "SpokenBossesAudio-*.zip");
                Is(bosses.Tag == "bosses-audio/v1.0.0" && asked.Count == 2, "another series of the same repository: no call more");
                Is(Throws(delegate { GitHub.Latest("x/y", @"^places-audio/v\d", "SpokenPlacesAudio-*.zip"); }, GitHub.NoStable) && asked.Count == 3, "a series in none: three pages at most (" + asked.Count + ")");
                Release betas = GitHub.Latest("x/y", @"^quests-audio/v\d", "SpokenQuestsAudioAll-*.zip", true);
                Is(betas.Tag == "quests-audio/v2.6.0" && betas.Test, "with test versions, the newest");
                GitHub.Forget();
                GitHub.Latest("x/y", @"^bosses-audio/v\d", "SpokenBossesAudio-*.zip");
                Is(asked.Count == 4, "forgotten: asked again");
            }
            finally
            {
                GitHub.FakeApi = null;
                GitHub.Forget();
            }
        }

        static void WebPages()
        {
            string refs = "001e# service=git-upload-pack\n0000015b1111111111111111111111111111111111111111 HEAD\0multi_ack\n" +
                "003f2222222222222222222222222222222222222222 refs/heads/main\n" +
                "00453333333333333333333333333333333333333333 refs/tags/quests-audio/v2.9.1\n" +
                "00484444444444444444444444444444444444444444 refs/tags/quests-audio/v2.9.1^{}\n" +
                "00465555555555555555555555555555555555555555 refs/tags/quests-audio/v2.10.0\n" +
                "004a6666666666666666666666666666666666666666 refs/tags/quests-audio-esMX/v9.0.0\n" +
                "00407777777777777777777777777777777777777777 refs/tags/spoken/v3.8.3\n0000";
            List<string> tags = GitHub.TagsIn(refs);
            Is(tags.Count == 4 && !tags.Exists(t => t.Contains("^")), "git's tags read, peeled ones once (" + string.Join(" ", tags.ToArray()) + ")");
            List<string> newest = GitHub.NewestFirst(tags, @"^quests-audio/v\d");
            Is(newest.Count == 2 && newest[0] == "quests-audio/v2.10.0", "the newest of a series by its version, not another language's");

            string page = "<div><ul><li class=\"Box-row\"><a href=\"/x/y/releases/download/quests-audio%2Fv2.10.0/SpokenQuestsAudioAll-2.10.0.zip\" rel=\"nofollow\">SpokenQuestsAudioAll-2.10.0.zip</a>" +
                "<span class=\"Truncate-text\">sha256:" + new string('b', 64) + "</span></li>" +
                "<li class=\"Box-row\"><a href=\"/x/y/archive/refs/tags/quests-audio/v2.10.0.zip\">Source code (zip)</a></li>" +
                "<li><a href=\"/x/y/releases/download/quests-audio%2Fv2.10.0/notes.txt\">notes.txt</a></li></ul></div>";
            List<Asset> assets = GitHub.ParseAssets(page, "x/y");
            Is(assets.Count == 2 && assets[0].Name == "SpokenQuestsAudioAll-2.10.0.zip" && assets[0].Sha256 == new string('b', 64)
                && assets[0].Url == "https://github.com/x/y/releases/download/quests-audio%2Fv2.10.0/SpokenQuestsAudioAll-2.10.0.zip" && assets[1].Sha256 == null,
                "a release page's files and sha256s, not its source code");
            Is(GitHub.ParseAssets(page, "other/repo").Count == 0, "only the repository's own downloads");
        }

        // A web server of our own on this computer, answering each request
        // with the next answer given: how a download is taken up again.
        static List<string> Serve(int port, params Func<string, byte[]>[] answers)
        {
            List<string> seen = new List<string>();
            System.Net.Sockets.TcpListener server = new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, port);
            server.Start();
            System.Threading.Thread worker = new System.Threading.Thread(delegate()
            {
                try
                {
                    foreach (Func<string, byte[]> answer in answers)
                        using (System.Net.Sockets.TcpClient client = server.AcceptTcpClient())
                        using (System.Net.Sockets.NetworkStream stream = client.GetStream())
                        {
                            StringBuilder head = new StringBuilder();
                            while (!head.ToString().EndsWith("\r\n\r\n")) { int b = stream.ReadByte(); if (b < 0) break; head.Append((char)b); }
                            lock (seen) seen.Add(head.ToString());
                            byte[] reply = answer(head.ToString());
                            try { stream.Write(reply, 0, reply.Length); } catch { }
                        }
                }
                catch { }
                finally { server.Stop(); }
            });
            worker.IsBackground = true;
            worker.Start();
            return seen;
        }

        static byte[] Reply(string status, string headers, byte[] body, int send)
        {
            byte[] head = Encoding.ASCII.GetBytes("HTTP/1.1 " + status + "\r\n" + headers + "Connection: close\r\n\r\n");
            byte[] all = new byte[head.Length + send];
            Buffer.BlockCopy(head, 0, all, 0, head.Length);
            if (send > 0) Buffer.BlockCopy(body, 0, all, head.Length, send);
            return all;
        }

        static void Resume()
        {
            byte[] payload = new byte[300000];
            new Random(7).NextBytes(payload);
            int port = 47000 + new Random().Next(2000);
            string url = "http://127.0.0.1:" + port + "/file.zip";
            string path = Path.Combine(root, "resume.part");

            // The first answer stops at 100 KB; the second gives the rest.
            List<string> seen = Serve(port,
                delegate(string head) { return Reply("200 OK", "Content-Length: 300000\r\n", payload, 100000); },
                delegate(string head)
                {
                    byte[] rest = payload.Skip(100000).ToArray();
                    return Reply("206 Partial Content", "Content-Range: bytes 100000-299999/300000\r\nContent-Length: 200000\r\n", rest, rest.Length);
                });
            Net.Download(url, path, null, null, 0, true);
            Is(File.ReadAllBytes(path).SequenceEqual(payload), "a download that stopped is taken up where it stopped");
            Is(seen.Count == 2 && seen[1].IndexOf("Range: bytes=100000-", StringComparison.OrdinalIgnoreCase) >= 0, "only the rest asked for");

            // Whole already: the server has nothing after it.
            port++;
            seen = Serve(port, delegate(string head) { return Reply("416 Range Not Satisfiable", "Content-Range: bytes */300000\r\nContent-Length: 0\r\n", null, 0); });
            Net.Download("http://127.0.0.1:" + port + "/file.zip", path, null, null, 0, true);
            Is(File.ReadAllBytes(path).SequenceEqual(payload) && seen.Count == 1, "a whole one is not downloaded again");

            // A server that gives all of it again, from the start.
            port++;
            File.WriteAllBytes(path, payload.Take(5000).ToArray());
            seen = Serve(port, delegate(string head) { return Reply("200 OK", "Content-Length: 300000\r\n", payload, payload.Length); });
            Net.Download("http://127.0.0.1:" + port + "/file.zip", path, null, null, 0, true);
            Is(File.ReadAllBytes(path).SequenceEqual(payload), "a server that ignores the Range: started again");

            // Without resume (a guide's): nothing kept, nothing tried twice.
            port++;
            File.Delete(path);
            Serve(port, delegate(string head) { return Reply("200 OK", "Content-Length: 300000\r\n", payload, 1000); });
            Is(Throws(delegate { Net.Download("http://127.0.0.1:" + port + "/file.zip", path, null, null, 0, false); }, null), "without resume, a download that stops fails");

            Release a = new Release { ZipUrl = "https://github.com/x/y/releases/download/v1/a.zip", Sha256 = new string('c', 64) };
            Release b = new Release { ZipUrl = "https://github.com/x/y/releases/download/v1/a.zip" };
            Release c = new Release { ZipUrl = "https://github.com/x/y/releases/download/v2/a.zip" };
            Is(Installer.PartPath(root, a) == Installer.PartPath(root, a) && Installer.PartPath(root, a) != Installer.PartPath(root, b)
                && Installer.PartPath(root, b) != Installer.PartPath(root, c), "one held part per file");
        }

        static void Room()
        {
            string temp = Path.Combine(root, "roomtemp"), addons = Path.Combine(root, "game", "Interface", "AddOns");
            Directory.CreateDirectory(temp);
            try
            {
                Environment.SetEnvironmentVariable("FUM_TEST_FREE", (300L * 1048576).ToString());
                Is(Throws(delegate { Installer.RoomToDownload(temp, addons, 1480L * 1048576, 0); }, "not room enough"), "1.5 GB with 300 MB free is refused before downloading");
                Is(!Throws(delegate { Installer.RoomToDownload(temp, addons, 40L * 1048576, 0); }, null), "40 MB with 300 MB free goes");
                Is(!Throws(delegate { Installer.RoomToDownload(temp, addons, -1, 0); }, null), "no size known: not checked before");
                string zip = MakeZip("room.zip", new Dictionary<string, string> { { "A/A.toc", "## Interface: 16001" } });
                Is(!Throws(delegate { Installer.RoomToUnpack(addons, zip); }, null), "a small zip unpacks");
                Environment.SetEnvironmentVariable("FUM_TEST_FREE", "1000");
                Is(Throws(delegate { Installer.RoomToUnpack(addons, zip); }, "not room enough"), "no room to unpack is said");
            }
            finally { Environment.SetEnvironmentVariable("FUM_TEST_FREE", null); }
            Is(Core.Bytes(1479966451) == "1.38 GB" && Core.Bytes(157070901) == "149.8 MB", "sizes in GB and MB");
        }

        static void RealGuides(string dir)
        {
            string addons = Path.Combine(root, "realguides", "Interface", "AddOns");
            foreach (string zip in Directory.GetFiles(dir, "*.zip"))
            {
                bool only = !Throws(delegate { Installer.OnlyGuides(zip); }, null);
                Placed placed = Installer.Put(addons, zip, null, Path.GetFileNameWithoutExtension(zip));
                string folder = placed.Folders[0];
                string said = Packs.Compiled(Path.Combine(addons, folder));
                Console.WriteLine("  " + Path.GetFileName(zip) + ": " + folder + ", " + (said == null ? "only what the compiler makes" : "carries " + said));
                Is(only && placed.Folders.Length == 1 && folder.StartsWith("PolestarPack_"), Path.GetFileName(zip) + " is one guide folder");
            }
        }

        static void Live()
        {
            Release api = GitHub.Latest("EllesmereGaming/EllesmereUI", null, null);
            Console.WriteLine("  EllesmereUI api: " + api.Tag + " " + api.ZipName + " " + api.Size + " (" + api.PickedBy + ")");
            bool apiOut = api.PickedBy.Contains("GitHub's page");
            if (apiOut) Console.WriteLine("  (GitHub's API limit is used up: its pages answered instead)");
            Is(api.ZipName != null && api.ZipName.EndsWith(".zip") && (apiOut || (api.Sha256 != null && api.Size > 1000000)) && api.PickedBy.Contains("release.json"), "EllesmereUI by the API");

            TrackedAddon polestar = TrackedAddon.ForRepo("fitzforge/polestar");
            Release pole = GitHub.Latest(polestar);
            Console.WriteLine("  Polestar api: " + pole.Tag + " " + pole.ZipName + " " + pole.Size + " " + pole.Sha256 + " (" + pole.PickedBy + ")");
            Is(pole.Tag.StartsWith("v") && pole.ZipName.StartsWith("Polestar-") && pole.Sha256 != null && pole.PickedBy.Contains("SHA256SUMS"), "Polestar by the API, checked against SHA256SUMS");

            Environment.SetEnvironmentVariable("FUM_NO_API", "1");
            GitHub.Forget();
            Release web = GitHub.Latest("EllesmereGaming/EllesmereUI", null, null);
            Console.WriteLine("  EllesmereUI web: " + web.Tag + " " + web.ZipName);
            Is(web.Tag == api.Tag && web.ZipName == api.ZipName && web.Sha256 == null, "EllesmereUI by GitHub's pages");
            try
            {
                Release poleWeb = GitHub.Latest(polestar);
                Console.WriteLine("  Polestar web: " + poleWeb.Tag + " " + poleWeb.ZipName + " " + poleWeb.Sha256);
                Is(poleWeb.Tag == pole.Tag && poleWeb.ZipName == pole.ZipName && poleWeb.Sha256 == pole.Sha256, "Polestar by GitHub's pages, sha256 from SHA256SUMS");
            }
            catch (Exception why)
            {
                // GitHub's "latest" may be the repository's data or library release: said, and checked later.
                Console.WriteLine("  Polestar web: " + why.Message);
                Is(why.Message.Contains("another of the repository's things"), "Polestar by GitHub's pages says why when latest is another thing");
            }
            Is(Throws(delegate { GitHub.Latest("EllesmereGaming/no-such-repo-here-0451", null, null); }, null), "no such repository, by the pages");
            Environment.SetEnvironmentVariable("FUM_NO_API", null);

            // Spoken and its voice packs: one repository, five series, one call.
            KnownRepo[] spoken = Pack.Parse(PackText())[0].Where(k => k.Repo == "rusty-key/spoken-wow").ToArray();
            Dictionary<string, Release> byApi = new Dictionary<string, Release>();
            int calls = GitHub.Calls;
            foreach (KnownRepo k in spoken)
            {
                Release r = GitHub.Latest(k.Repo, k.Series, k.Zip);
                byApi[k.Key] = r;
                Console.WriteLine("  " + k.Title + ": " + r.Tag + " " + r.ZipName + " " + (r.Size > 0 ? Core.Bytes(r.Size) : "?") + " (" + r.PickedBy + ")");
                Is(System.Text.RegularExpressions.Regex.IsMatch(r.Tag, k.Series) && GitHub.Like(r.ZipName, k.Zip) && r.Sha256 != null, k.Title + " found, with its sha256");
            }
            Console.WriteLine("  Spoken's five: " + (GitHub.Calls - calls) + " API call(s)");
            Is(GitHub.Calls - calls <= 2, "Spoken's five in one or two API calls");
            Environment.SetEnvironmentVariable("FUM_NO_API", "1");
            GitHub.Forget();
            foreach (KnownRepo k in spoken)
            {
                Release r = GitHub.Latest(k.Repo, k.Series, k.Zip);
                Release api2 = byApi[k.Key];
                Console.WriteLine("  " + k.Title + " web: " + r.Tag + " " + r.ZipName + " (" + r.PickedBy + ")");
                Is(r.Tag == api2.Tag && r.ZipName == api2.ZipName && r.Sha256 == api2.Sha256, k.Title + " by GitHub's pages, the same as the API's");
            }
            Environment.SetEnvironmentVariable("FUM_NO_API", null);

            // A download taken up again through GitHub's redirect.
            string full = Path.Combine(root, "pole-full.zip"), half = Path.Combine(root, "pole.part");
            Net.Download(pole.ZipUrl, full, null, null, 0, true);
            byte[] all = File.ReadAllBytes(full);
            File.WriteAllBytes(half, all.Take(all.Length / 2).ToArray());
            long first = -1;
            Net.Download(pole.ZipUrl, half, delegate(long done, long total) { if (first < 0) first = done; }, null, 0, true);
            Console.WriteLine("  resumed at " + (all.Length / 2) + " of " + all.Length + ", first count " + first);
            Is(Core.Sha256Of(half) == pole.Sha256 && first > all.Length / 2, "a download taken up again through GitHub's redirect");
            bool final = false;
            try { GitHub.Latest("EllesmereGaming/no-such-repo-here-0451", null, null); }
            catch (Final) { final = true; }
            Is(final, "no such repository, by the API");

            PackIndex index = Packs.Fetch();
            Console.WriteLine("  polestar.guide: " + index.Packs.Count + " guides, " + index.Revoked.Count + " pulled, made " + index.Generated.ToString("u"));
            Is(index.Packs.Count > 0 && index.Packs.All(p => p.Folders.Contains("PolestarPack_" + p.Id)), "polestar.guide's signed list");
            PackIndex again = Packs.Fetch();
            Is(again.Generated == index.Generated, "fetched again (304 or the same list)");
        }

        static void RealIndex(string dir)
        {
            byte[] body = File.ReadAllBytes(Path.Combine(dir, "index.json")), sig = File.ReadAllBytes(Path.Combine(dir, "index.json.sig"));
            PackIndex index = Packs.Verify(body, sig, null, DateTime.UtcNow);
            Console.WriteLine("  index: " + index.Packs.Count + " guides: " + string.Join(", ", index.Packs.Select(p => p.Id + " " + p.Version).ToArray()));
            Is(index.Packs.Count >= 1, "the real list's signature holds");
            byte[] tampered = (byte[])body.Clone();
            tampered[tampered.Length / 2] ^= 1;
            Is(Throws(delegate { Packs.Verify(tampered, sig, null, DateTime.UtcNow); }, "does not match"), "a changed byte is refused");
            Is(Throws(delegate { Packs.Verify(body, sig, null, index.Expires.AddMinutes(1)); }, "expired"), "an expired list is refused");
            Is(Throws(delegate { Packs.Verify(body, sig, index.Generated.AddSeconds(1), DateTime.UtcNow); }, "older"), "an older list than the last is refused");
            string otherKey = Encoding.UTF8.GetString(sig).Replace("polestar-1", "polestar-9");
            Is(Throws(delegate { Packs.Verify(body, Encoding.UTF8.GetBytes(otherKey), null, DateTime.UtcNow); }, "key"), "an unknown key is refused");
            string swapped = Encoding.UTF8.GetString(sig).Replace("polestar-1", "polestar-2");
            Is(Throws(delegate { Packs.Verify(body, Encoding.UTF8.GetBytes(swapped), null, DateTime.UtcNow); }, "not valid"), "the other pinned key does not pass it");
        }

        // A ForeverUI release made by tools/make_release.py, as the app reads
        // one: release.json names the zip, SHA256SUMS agrees, its four folders go in.
        static void OurRelease(string dir)
        {
            string chosen = GitHub.ForeverIn(File.ReadAllText(Path.Combine(dir, "release.json")));
            Dictionary<string, string> sums = GitHub.ParseSums(File.ReadAllText(Path.Combine(dir, "SHA256SUMS")));
            string zip = chosen == null ? null : Path.Combine(dir, chosen);
            Console.WriteLine("  release.json picks " + chosen);
            Is(zip != null && File.Exists(zip) && System.Text.RegularExpressions.Regex.IsMatch(chosen, @"^ForeverUI-\d+\.\d+\.\d+\.zip$"), "release.json picks our zip for WoW Forever");
            Is(chosen != null && sums.ContainsKey(chosen) && sums[chosen] == Core.Sha256Of(zip), "SHA256SUMS agrees with the zip");
            string exe = Path.Combine(dir, "ForeverUIManager.exe");
            Is(sums.ContainsKey("ForeverUIManager.exe") && sums["ForeverUIManager.exe"] == Core.Sha256Of(exe), "SHA256SUMS agrees with the exe");
            if (zip != null) RealZip(zip, 4);   // ForeverUI, XPbar, Quest Log, Trainer
        }

        static void RealZip(string zip, int expected)
        {
            string addons = Path.Combine(root, "real", "Interface", "AddOns");
            Placed placed = Installer.Put(addons, zip, null, "Real");
            Console.WriteLine("  real zip: " + placed.Folders.Length + " folders, " + placed.Skipped + " left out");
            Is(placed.Folders.Length == expected, expected + " folders");
            int files = Directory.GetFiles(addons, "*", SearchOption.AllDirectories).Length;
            using (ZipArchive archive = ZipFile.OpenRead(zip))
                Is(files == archive.Entries.Count(e => e.Name != "") - placed.Skipped, "every file out (" + files + ")");
            foreach (string folder in placed.Folders)
            {
                Toc toc = Installer.ReadToc(Path.Combine(addons, folder));
                Is(toc != null && Installer.ForeverInterface(toc.Interface) != null, folder + "'s .toc is for Forever");
            }
        }
    }
}
