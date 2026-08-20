// Model.js is QML JavaScript: plain ES5 apart from the .pragma line, so it can
// be exercised in a normal JS runtime. Keeping the helpers free of QML types is
// what makes that possible — and what makes the parsing testable at all.
const src = Deno.readTextFileSync(new URL("../Model.js", import.meta.url))
  .replace(".pragma library", "");
const M = {};
new Function("exports", src + `
Object.assign(exports, {deviceLabel, deviceStateText, selectedDevice, effectiveCamera,
  sizeOptions, shortlistSizes, formatUptime, blockingIssue, missingPackagesText, safeParse,
  camerasForFacing, firstReadyDevice, facingLabel});`)(M);

const cams = [
  {id: "0", facing: "back",  sizes: ["4080x3060","1920x1080","1280x720","640x480"]},
  {id: "1", facing: "front", sizes: ["3264x2448","1920x1080","1280x720"]},
  {id: "2", facing: "front", sizes: ["2880x1980"]},
];
const devs = [
  {serial: "AAA", state: "unauthorized", model: "", ready: false},
  {serial: "BBB", state: "device", model: "SM A546E", ready: true},
];

let fails = 0;
const check = (label, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (!ok) fails++;
  console.log(`${ok ? "  pass  " : "  FAIL  "}${label}` + (ok ? "" : `  got=${JSON.stringify(got)} want=${JSON.stringify(want)}`));
};

check("deviceLabel uses model",        M.deviceLabel(devs[1]), "SM A546E");
check("deviceLabel falls to serial",   M.deviceLabel(devs[0]), "AAA");
check("deviceLabel of nothing",        M.deviceLabel(null), "");
check("state text is actionable",      M.deviceStateText("unauthorized"), "Check phone screen");
check("unknown state passes through",  M.deviceStateText("weird"), "weird");
check("selectedDevice skips unready",  M.selectedDevice(devs, "").serial, "BBB");
check("selectedDevice honours serial", M.selectedDevice(devs, "BBB").serial, "BBB");
check("unready serial falls back",     M.selectedDevice(devs, "AAA").serial, "BBB");
check("no devices -> null",            M.selectedDevice([], ""), null);
check("effectiveCamera by facing",     M.effectiveCamera(cams, "front", "").id, "1");
check("explicit id overrides facing",  M.effectiveCamera(cams, "front", "0").id, "0");
check("unknown facing -> null",        M.effectiveCamera(cams, "nope", ""), null);
check("sizeOptions are per-camera",    M.sizeOptions(cams, "front", ""), ["3264x2448","1920x1080","1280x720"]);
check("sizeOptions unknown -> []",     M.sizeOptions(cams, "nope", ""), []);
check("shortlist keeps max first",     M.shortlistSizes(cams[0].sizes, 3)[0], "4080x3060");
check("shortlist dedupes",             M.shortlistSizes(cams[0].sizes, 6), ["4080x3060","1920x1080","1280x720","640x480"]);
check("shortlist respects limit",      M.shortlistSizes(cams[0].sizes, 2).length, 2);
check("uptime under an hour",          M.formatUptime(75), "1:15");
check("uptime over an hour",           M.formatUptime(3725), "1:02:05");
check("uptime rejects nonsense",       M.formatUptime("x"), "");
check("blocking ignores warn",         M.blockingIssue([{severity:"warn"}]), null);
check("blocking finds blocked",        M.blockingIssue([{severity:"warn"},{severity:"blocked",code:"b"}]).code, "b");
check("missing packages prose",        M.missingPackagesText(["scrcpy","adb","v4l2loopback-dkms"]), "scrcpy, adb and v4l2loopback-dkms");
check("single package prose",          M.missingPackagesText(["scrcpy"]), "scrcpy");
check("safeParse survives garbage",    M.safeParse("not json", []), []);
check("safeParse survives empty",      M.safeParse("", []), []);
check("safeParse reads json",          M.safeParse('{"a":1}', {}).a, 1);
check("camerasForFacing finds both",   M.camerasForFacing(cams, "front").length, 2);
check("facingLabel capitalises",       M.facingLabel("back"), "Back");

console.log(fails === 0 ? "\nALL PASS" : `\n${fails} FAILED`);
if (fails) Deno.exit(1);
