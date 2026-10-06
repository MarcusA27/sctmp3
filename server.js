import express from "express";
import { spawn } from "node:child_process";
import { mkdtemp, rm, readdir, stat } from "node:fs/promises";
import { createReadStream } from "node:fs";
import { tmpdir } from "node:os";
import { join, basename } from "node:path";
import { fileURLToPath } from "node:url";
import { dirname } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const app = express();
const PORT = process.env.PORT || 8750;

app.use(express.json());
app.use(express.static(join(__dirname, "public")));

const SC_HOST = /^(https?:\/\/)?([\w-]+\.)*soundcloud\.com\//i;
const isSoundcloud = (u) => typeof u === "string" && SC_HOST.test(u.trim());

function run(cmd, args, { onLine } = {}) {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args);
    let out = "";
    let err = "";
    p.stdout.on("data", (d) => {
      out += d;
    });
    p.stderr.on("data", (d) => {
      const s = d.toString();
      err += s;
      if (onLine) s.split("\n").forEach((l) => l.trim() && onLine(l.trim()));
    });
    p.on("error", reject);
    p.on("close", (code) =>
      code === 0 ? resolve(out) : reject(new Error(err || `${cmd} exited ${code}`))
    );
  });
}

// Metadata preview so the UI can show a track card before downloading.
app.post("/api/info", async (req, res) => {
  const url = req.body?.url?.trim();
  if (!isSoundcloud(url)) return res.status(400).json({ error: "Not a SoundCloud URL" });
  try {
    const raw = await run("yt-dlp", [
      "--dump-single-json",
      "--flat-playlist",
      "--no-warnings",
      url,
    ]);
    const j = JSON.parse(raw);
    const entries = j.entries || null;
    res.json({
      title: j.title,
      uploader: j.uploader || j.uploader_id || "",
      thumbnail: j.thumbnail || j.thumbnails?.at(-1)?.url || "",
      duration: j.duration || null,
      isPlaylist: Array.isArray(entries),
      count: Array.isArray(entries) ? entries.length : 1,
    });
  } catch (e) {
    res.status(500).json({ error: String(e.message || e).slice(0, 400) });
  }
});

// Download + convert. Streams a single .mp3, or a .zip for playlists.
app.get("/api/download", async (req, res) => {
  const url = (req.query.url || "").toString().trim();
  const quality = req.query.q === "128" ? "128K" : "320K";
  if (!isSoundcloud(url)) return res.status(400).send("Not a SoundCloud URL");

  const work = await mkdtemp(join(tmpdir(), "sctmp3-"));
  try {
    await run("yt-dlp", [
      "-x",
      "--audio-format", "mp3",
      "--audio-quality", "0",
      "--postprocessor-args", `ffmpeg:-b:a ${quality}`,
      "--embed-thumbnail",
      "--embed-metadata",
      "--no-playlist-reverse",
      "--no-warnings",
      "-o", join(work, "%(playlist_index)s-%(title)s.%(ext)s"),
      url,
    ]);

    const files = (await readdir(work)).filter((f) => f.toLowerCase().endsWith(".mp3"));
    if (files.length === 0) throw new Error("No audio produced");

    if (files.length === 1) {
      const f = files[0];
      const name = f.replace(/^NA-/, "").replace(/^\d+-/, "");
      const size = (await stat(join(work, f))).size;
      res.setHeader("Content-Type", "audio/mpeg");
      res.setHeader("Content-Length", size);
      res.setHeader(
        "Content-Disposition",
        `attachment; filename*=UTF-8''${encodeURIComponent(name)}`
      );
      const stream = createReadStream(join(work, f));
      stream.pipe(res);
      stream.on("close", () => rm(work, { recursive: true, force: true }));
      return;
    }

    // Playlist -> zip
    const zipName = "soundcloud-tracks.zip";
    const zipPath = join(work, zipName);
    await run("zip", ["-j", "-q", zipPath, ...files.map((f) => join(work, f))]);
    const size = (await stat(zipPath)).size;
    res.setHeader("Content-Type", "application/zip");
    res.setHeader("Content-Length", size);
    res.setHeader("Content-Disposition", `attachment; filename="${zipName}"`);
    const stream = createReadStream(zipPath);
    stream.pipe(res);
    stream.on("close", () => rm(work, { recursive: true, force: true }));
  } catch (e) {
    await rm(work, { recursive: true, force: true });
    if (!res.headersSent) res.status(500).send(String(e.message || e).slice(0, 400));
  }
});

app.listen(PORT, () =>
  console.log(`sctmp3 running → http://localhost:${PORT}`)
);
