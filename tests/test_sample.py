import importlib.machinery, importlib.util, json, pathlib, subprocess, sys, unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
def load(name):
    spec = importlib.util.spec_from_loader(name, importlib.machinery.SourceFileLoader(name, str(ROOT / "bin" / name)))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
S = load("dw-sample"); I = load("dw-sysinfo")


class Sample(unittest.TestCase):
    def test_cpu_percent(self):
        a = S.cpu_times("cpu  100 0 100 800 0 0 0 0 0 0"); b = S.cpu_times("cpu  150 0 150 900 0 0 0 0 0 0")
        self.assertEqual(S.cpu_percent(a, b), 50.0)
        self.assertIsNone(S.cpu_percent(a, a)); self.assertIsNone(S.cpu_times("intr 1 2 3"))

    def test_mem_and_net_and_route(self):
        m = S.mem_info("MemTotal:       1000 kB\nMemFree:  100 kB\nMemAvailable:    250 kB\n")
        self.assertEqual(m, {"pct": 75.0, "used": 750 * 1024, "total": 1000 * 1024})
        self.assertIsNone(S.mem_info("garbage"))
        dev = "Inter-|...\n face |...\n    lo:  200 5 0 0 0 0 0 0  200 5 0 0 0 0 0 0\nwlp0s20f3: 123456 9 0 0 0 0 0 0 7890 3 0 0 0 0 0 0\n"
        self.assertEqual(S.net_counters(dev, "wlp0s20f3"), {"iface": "wlp0s20f3", "rx": 123456, "tx": 7890})
        self.assertIsNone(S.net_counters(dev, "eth9"))
        self.assertEqual(S.default_iface("default via 192.168.1.1 dev wlp0s20f3 proto dhcp src 1.2.3.4 metric 600\n"), "wlp0s20f3")
        self.assertIsNone(S.default_iface(""))

    def test_battery(self):
        b = S.battery_from({"capacity": "38\n", "status": "Discharging\n", "current_now": "1000000", "voltage_now": "12000000", "charge_now": "2000000", "charge_full": "4000000"})
        self.assertEqual((b["pct"], b["status"], b["watts"]), (38, "Discharging", 12.0)); self.assertEqual(b["hours"], 2.0)
        c = S.battery_from({"capacity": "50", "status": "Charging", "power_now": "20000000", "energy_now": "30000000", "energy_full": "60000000"})
        self.assertEqual((c["watts"], c["hours"]), (20.0, 1.5))
        self.assertEqual(S.battery_from({"capacity": "99", "status": "Full"})["hours"], None)
        self.assertIsNone(S.battery_from({"status": "x"}))

    def test_gpu_and_temp(self):
        self.assertEqual(S.gpu_from_nvidia("55, 1234, 8192\n"), {"pct": 55, "mem_used": 1234, "mem_total": 8192, "source": "nvidia"})
        self.assertIsNone(S.gpu_from_nvidia("N/A"))
        self.assertEqual(S.temp_pick([("acpitz", 56000), ("nvme", 34850), ("coretemp", 63000)]), {"c": 63.0, "source": "coretemp"})
        self.assertEqual(S.temp_pick([("nvme", 34850)]), {"c": 34.9, "source": "nvme"}); self.assertIsNone(S.temp_pick([("x", None)]))

    def test_live_sample_shape(self):
        out = json.loads(subprocess.run([sys.executable, str(ROOT / "bin" / "dw-sample")], capture_output=True, text=True, timeout=10).stdout)
        for k in ("t", "cpu", "mem", "load", "temp", "net", "battery", "gpu"): self.assertIn(k, out)
        self.assertTrue(0 <= out["cpu"]["pct"] <= 100); self.assertTrue(out["mem"]["total"] > 0)


class Sysinfo(unittest.TestCase):
    def test_flatten(self):
        mods = [{"type": "OS", "result": {"prettyName": "Omarchy", "version": ""}}, {"type": "Kernel", "result": {"name": "Linux", "release": "7.2.3"}},
                {"type": "Uptime", "result": {"uptime": 2805880}}, {"type": "Packages", "result": {"all": 1309, "pacman": 1309}},
                {"type": "CPU", "result": {"cpu": "Intel(R) Core(TM) i5", "cores": {"logical": 8}}}, {"type": "GPU", "result": [{"name": "Intel UHD"}, {"name": None}]},
                {"type": "Memory", "result": {"total": 16 * 1024**3, "used": 4 * 1024**3}},
                {"type": "Disk", "result": [{"mountpoint": "/boot", "bytes": {"total": 10, "used": 1}}, {"mountpoint": "/", "bytes": {"total": 200 * 1024**3, "used": 100 * 1024**3}}]},
                {"type": "LocalIp", "result": [{"name": "ts0", "ipv4": "100.1.1.1/32"}, {"name": "wl", "defaultRoute": {"ipv4": True}, "ipv4": "192.168.1.5/24"}]},
                {"type": "Battery", "result": [{"capacity": 48.0, "status": "Charging"}]}, {"type": "Break", "error": "x"}]
        f = I.flatten(mods)
        self.assertEqual(f["os"], "Omarchy"); self.assertEqual(f["kernel"], "Linux 7.2.3"); self.assertEqual(f["uptime"], "46m")
        self.assertEqual(f["packages"], "1309 (pacman)"); self.assertEqual(f["cpu"], "Intel Core i5 (8)"); self.assertEqual(f["gpu"], "Intel UHD")
        self.assertEqual(f["memory"], "4.0 GiB / 16.0 GiB (25%)"); self.assertEqual(f["disk"], "100.0 GiB / 200.0 GiB (50%)")
        self.assertEqual(f["ip"], "192.168.1.5"); self.assertEqual(f["battery"], "48% [Charging]")
        self.assertEqual(I.fmt_uptime(90061000), "1d 1h 1m"); self.assertEqual(I.fmt_uptime(3600000), "1h 0m")

    def test_live(self):
        out = json.loads(subprocess.run([sys.executable, str(ROOT / "bin" / "dw-sysinfo"), "--logo", "omarchy"], capture_output=True, text=True, timeout=10).stdout)
        self.assertTrue(out["host"]); self.assertIn("kernel", out); self.assertTrue(len(out["logo"]) > 5)
        self.assertEqual(json.loads(subprocess.run([sys.executable, str(ROOT / "bin" / "dw-sysinfo"), "--logo", "none"], capture_output=True, text=True, timeout=10).stdout)["logo"], [])


if __name__ == "__main__":
    unittest.main()
