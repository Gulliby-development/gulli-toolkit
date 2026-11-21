import io
import json
import os
import sys
import unittest
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import upload as U  # noqa: E402

CONFIG = {"game_version": "1.60.1", "toolkit": {"id": 1, "slug": "gulli-toolkit"},
          "separate": {"CraftProfit": {"id": 2}, "Legacy": {"id": None}}}


class Targets(unittest.TestCase):
    def test_a_separate_module_goes_to_its_own_project(self):
        self.assertEqual(U.targets("CraftProfit-v1.9.0", CONFIG), ["CraftProfit"])

    def test_the_core_and_small_modules_go_to_the_toolkit(self):
        self.assertEqual(U.targets("Core-v1.17.0", CONFIG), ["toolkit"])
        self.assertEqual(U.targets("QuickChat-v2.0.2", CONFIG), ["toolkit"])

    def test_each_project_has_its_own_upload_queue(self):
        self.assertEqual(U.route("CraftProfit-v1.9.0", CONFIG), "CraftProfit")
        self.assertEqual(U.route("Core-v1.17.0", CONFIG), "toolkit")
        self.assertEqual(U.route("XP-v1.2.0", CONFIG), "toolkit")
        self.assertEqual(U.route("all", CONFIG), "all")

    def test_toolkit_uploads_the_toolkit(self):
        self.assertEqual(U.targets("toolkit", CONFIG), ["toolkit"])
        self.assertEqual(U.route("toolkit", CONFIG), "toolkit")

    def test_only_toolkit_releases_after_the_last_toolkit_upload_count(self):
        groups = {"Core": {"tag_name": "Core-v1.33.0", "published_at": "2026-11-18T16:52:35Z"},
                  "XP": {"tag_name": "XP-v1.15.0", "published_at": "2026-11-18T16:42:52Z"},
                  "Mail": {"tag_name": "Mail-v1.10.3", "published_at": "2026-11-18T00:34:32Z"},
                  "CraftProfit": {"tag_name": "CraftProfit-v1.15.0", "published_at": "2026-11-18T17:00:00Z"}}
        self.assertEqual(U.changed_groups(groups, CONFIG["separate"], "2026-11-18T16:00:00Z"), ["Core", "XP"])
        self.assertEqual(U.changed_groups(groups, CONFIG["separate"], "2026-11-18T17:00:00Z"), [])
        self.assertEqual(U.changed_groups(groups, CONFIG["separate"], None), ["Core", "Mail", "XP"])
        self.assertEqual(U.toolkit_display("1.33.0", ["Core", "XP"], groups), "Gulli Toolkit 1.33.0 (XP 1.15.0)")
        self.assertEqual(U.toolkit_display("1.33.0", ["Core"], groups), "Gulli Toolkit 1.33.0")
        self.assertEqual(U.toolkit_display("1.33.0", ["Mail", "XP"], groups, most=1),
                         "Gulli Toolkit 1.33.0 (Mail 1.10.3 +1)")

    def test_all_is_every_project(self):
        self.assertEqual(U.targets("all", CONFIG), ["toolkit", "CraftProfit", "Legacy"])

    def test_a_tag_that_is_no_release_stops(self):
        with self.assertRaises(SystemExit):
            U.targets("bundle", CONFIG)

    def test_the_real_config_reads_and_has_the_separate_projects(self):
        with open(U.CONFIG) as f:
            config = json.load(f)
        self.assertEqual(sorted(config["separate"]), ["CraftProfit", "Crates", "DungeonPrep", "GroupBuffs", "MyBisList", "VendorFlip", "WorthIt", "WritRunner"])
        for name in config["separate"]:
            self.assertTrue(os.path.isdir("Gulli-" + name), name)


class Version(unittest.TestCase):
    V = [{"id": 1, "name": "1.15.7", "gameVersionTypeID": 67}, {"id": 2, "name": "1.60.1", "gameVersionTypeID": 99}]

    def test_the_one_named_version(self):
        self.assertEqual(U.pick_version(self.V, "1.60.1"), 2)

    def test_a_fixed_id_wins(self):
        self.assertEqual(U.pick_version(self.V, "1.60.1", 7), 7)

    def test_none_or_two_named_stops(self):
        with self.assertRaises(SystemExit):
            U.pick_version(self.V, "1.60.2")
        with self.assertRaises(SystemExit):
            U.pick_version(self.V + [{"id": 3, "name": "1.60.1"}], "1.60.1")


class Upload(unittest.TestCase):
    def test_metadata_links_a_separate_project_to_the_toolkit(self):
        m = U.metadata("Gulli-Legacy 1.3.0", "notes", 2, "gulli-toolkit")
        self.assertEqual(m["gameVersions"], [2])
        self.assertEqual(m["releaseType"], "release")
        self.assertEqual(m["relations"]["projects"][0], {"slug": "gulli-toolkit", "type": "optionalDependency"})
        self.assertNotIn("relations", U.metadata("Gulli Toolkit 1.17.0", "notes", 2))

    def test_metadata_adds_the_other_optional_projects(self):
        m = U.metadata("Gulli-Crates 1.0.0", "notes", 2, "gulli-toolkit", ["auctionator"])
        self.assertEqual([p["slug"] for p in m["relations"]["projects"]], ["gulli-toolkit", "auctionator"])

    def test_multipart_holds_the_metadata_and_the_file(self):
        body, ctype = U.multipart({"metadata": "{}"}, "a.zip", b"ZIPDATA")
        self.assertTrue(ctype.startswith("multipart/form-data; boundary="))
        self.assertIn(b'name="metadata"', body)
        self.assertIn(b'filename="a.zip"', body)
        self.assertIn(b"ZIPDATA", body)

    def test_the_toolkit_zip_leaves_out_the_separate_modules(self):
        def rel(tag):
            return {"tag_name": tag}
        zips = {}
        for tag, folder in [("Core-v1.0.0", "Gulli-Toolkit"), ("XP-v1.0.0", "Gulli-XP"), ("CraftProfit-v1.0.0", "Gulli-CraftProfit")]:
            buf = io.BytesIO()
            with zipfile.ZipFile(buf, "w") as z:
                z.writestr(folder + "/" + folder + ".toc", "## Interface: 16001\n")
            zips[tag] = buf.getvalue()
        real = U.B.zip_of
        U.B.zip_of = lambda r, t: (r["tag_name"] + ".zip", zips[r["tag_name"]])
        try:
            groups = {"Core": rel("Core-v1.0.0"), "XP": rel("XP-v1.0.0"), "CraftProfit": rel("CraftProfit-v1.0.0")}
            data, lines = U.toolkit_zip(groups, CONFIG["separate"], None)
        finally:
            U.B.zip_of = real
        names = zipfile.ZipFile(io.BytesIO(data)).namelist()
        self.assertIn("Gulli-XP/Gulli-XP.toc", names)
        self.assertFalse(any(n.startswith("Gulli-CraftProfit/") for n in names))
        self.assertEqual(lines, ["- Gulli-Toolkit 1.0.0", "- Gulli-XP 1.0.0"])


if __name__ == "__main__":
    unittest.main()
