import importlib.machinery, importlib.util, pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_loader("dw_weather", importlib.machinery.SourceFileLoader("dw_weather", str(ROOT / "bin" / "dw-weather")))
W = importlib.util.module_from_spec(spec); spec.loader.exec_module(W)


class Weather(unittest.TestCase):
    def test_wmo(self):
        self.assertEqual(W.wmo_describe(0, True)[:2], ("Clear", "clear")); self.assertNotEqual(W.wmo_describe(0, True)[2], W.wmo_describe(0, False)[2])
        self.assertEqual(W.wmo_describe(2)[1], "partly"); self.assertEqual(W.wmo_describe(45)[1], "fog"); self.assertEqual(W.wmo_describe(55)[1], "drizzle")
        self.assertEqual(W.wmo_describe(65)[0], "Heavy rain"); self.assertEqual(W.wmo_describe(61)[0], "Rain"); self.assertEqual(W.wmo_describe(75)[1], "snow")
        self.assertEqual(W.wmo_describe(82)[1], "rain"); self.assertEqual(W.wmo_describe(96)[1], "storm"); self.assertEqual(W.wmo_describe("x")[0], "Unknown")

    def test_place_helpers(self):
        self.assertEqual(W.slug("Tokyo, Japan"), "tokyo-japan"); self.assertEqual(W.split_place("Tokyo, Japan"), ("Tokyo", "Japan")); self.assertEqual(W.split_place("Osaka"), ("Osaka", ""))
        res = [{"name": "Tokyo", "country": "Papua New Guinea", "country_code": "PG"}, {"name": "Tokyo", "country": "Japan", "country_code": "JP", "admin1": "Tokyo"}]
        self.assertEqual(W.pick_geo(res, "Tokyo, Japan")["country"], "Japan"); self.assertEqual(W.pick_geo(res, "Tokyo, jp")["country"], "Japan")
        self.assertEqual(W.pick_geo(res, "Tokyo")["country"], "Papua New Guinea"); self.assertIsNone(W.pick_geo([], "x"))

    def test_parse_forecast(self):
        data = {"current": {"time": "2026-09-10T08:00", "temperature_2m": 19.5, "apparent_temperature": 21.3, "relative_humidity_2m": 88, "is_day": 0, "precipitation": 0.0, "weather_code": 2, "wind_speed_10m": 5.8},
                "hourly": {"time": ["2026-09-10T08:00", "2026-09-10T09:00", "2026-09-10T10:00"], "temperature_2m": [19.5, 20.1, 21.0], "precipitation_probability": [10, 20, 30], "weather_code": [2, 61, 95]}}
        out = W.parse_forecast(data, "metric", 2)
        self.assertEqual(out["current"]["desc"], "Partly cloudy"); self.assertFalse(out["current"]["isDay"]); self.assertEqual(out["units"], {"temp": "°C", "wind": "km/h"})
        self.assertEqual(len(out["hourly"]), 2); self.assertEqual(out["hourly"][1], {"time": "09:00", "temp": 20.1, "pop": 20, "code": 61, "icon": W.ICONS["rain"][0], "group": "rain"})
        self.assertEqual(W.parse_forecast(data, "imperial", 12)["units"]["temp"], "°F"); self.assertEqual(len(W.parse_forecast(data, "metric", 12)["hourly"]), 3)
        self.assertEqual(W.parse_forecast({}, "metric", 3)["current"]["desc"], "Unknown")


if __name__ == "__main__":
    unittest.main()
