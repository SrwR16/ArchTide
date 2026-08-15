#!/usr/bin/env python3
"""Download a Wallpaper Engine wallpaper to ~/Pictures/Wallpapers/.

Usage:
    download_wpe_wallpaper.py <workshop_id> [--dest <path>] [--quality preview|full]

Quality modes:
  preview  (default): Copies the preview file (fast, low-res for scene wallpapers).
  full:              For scene wallpapers, renders a screenshot at monitor
                     resolution via linux-wallpaperengine. For web/preset,
                     copies all project files recursively.

For video wallpapers: copies the .mp4/.webm file directly (always full quality).
For scene wallpapers with --quality full: renders screenshot via linux-wallpaperengine.
For scene wallpapers with --quality preview: copies the preview gif/jpg.
For web wallpapers with --quality full: copies all project files recursively.
For preset wallpapers: resolves dependency and downloads the base wallpaper.
"""
import os
import sys
import json
import shutil
import subprocess
import argparse
import time


def find_workshop_paths():
    roots = [
        "/mnt/01DA34356F1F3C40/SteamLibrary/steamapps/workshop/content/431960",
        os.path.expanduser("~/.local/share/Steam/steamapps/workshop/content/431960"),
        os.path.expanduser("~/.steam/steam/steamapps/workshop/content/431960"),
        os.path.expanduser("~/.steam/root/steamapps/workshop/content/431960"),
    ]
    config_path = os.path.expanduser("~/.config/archtide/config.json")
    if os.path.exists(config_path):
        try:
            with open(config_path, "r") as f:
                cfg = json.load(f)
                assets_path = cfg.get("background", {}).get("wallpaperEngineAssetsPath", "")
                if assets_path:
                    workshop_path = assets_path.replace("common/wallpaper_engine/assets", "workshop/content/431960")
                    workshop_path = workshop_path.replace("common/wallpaper_engine", "workshop/content/431960")
                    if os.path.exists(workshop_path) and workshop_path not in roots:
                        roots.insert(0, workshop_path)
        except Exception:
            pass
    return [r for r in roots if os.path.exists(r)]


def find_assets_dir():
    config_path = os.path.expanduser("~/.config/archtide/config.json")
    if os.path.exists(config_path):
        try:
            with open(config_path) as f:
                cfg = json.load(f)
            assets_path = cfg.get("background", {}).get("wallpaperEngineAssetsPath", "")
            if assets_path and os.path.exists(assets_path):
                return assets_path
        except Exception:
            pass
    for wp_root in find_workshop_paths():
        for a, b in [
            ("workshop/content/431960", "common/wallpaper_engine/assets"),
            ("workshop/content/431960", "common/wallpaper_engine"),
        ]:
            candidate = wp_root.replace(a, b)
            if os.path.exists(candidate):
                return candidate
    return None


def get_primary_monitor():
    try:
        result = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True, timeout=5)
        monitors = json.loads(result.stdout)
        for m in monitors:
            if m.get("focused"):
                return m["name"]
        if monitors:
            return monitors[0]["name"]
    except Exception:
        return None

def is_wpe_running_for(wp_dir):
    try:
        result = subprocess.run(["pgrep", "-a", "-f", "linux-wallpaperengine"], capture_output=True, text=True, timeout=5)
        for line in result.stdout.splitlines():
            if wp_dir in line:
                return True
        return False
    except Exception:
        return False

def capture_with_grim(monitor, output_path):
    try:
        subprocess.run(["grim", "-o", monitor, output_path], capture_output=True, timeout=15)
        return os.path.exists(output_path) and os.path.getsize(output_path) > 0
    except Exception:
        return False


def find_wallpaper_dir(wp_id):
    for root in find_workshop_paths():
        candidate = os.path.join(root, wp_id)
        if os.path.isdir(candidate) and os.path.exists(os.path.join(candidate, "project.json")):
            return candidate
    return None


def notify(summary, body="", urgency="normal"):
    try:
        cmd = ["notify-send", "-a", "WPE Download", "-u", urgency, summary]
        if body:
            cmd.append(body)
        subprocess.run(cmd, timeout=5)
    except Exception:
        pass


def sanitize_filename(name):
    for ch in ['/', '\\', ':', '*', '?', '"', '<', '>', '|']:
        name = name.replace(ch, '_')
    return name.strip()


def get_monitor_resolution(monitor):
    try:
        result = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True, timeout=5)
        for m in json.loads(result.stdout):
            if m.get("name") == monitor:
                return m["width"], m["height"]
        return 1920, 1080
    except Exception:
        return 1920, 1080


def render_scene_screenshot(wp_id, wp_dir, assets_dir, output_path, timeout=30):
    monitor = get_primary_monitor()
    if not monitor:
        return False

    # Method 1: linux-wallpaperengine --screenshot (reads from FBO)
    cmd = [
        "linux-wallpaperengine",
        "--screenshot", output_path,
        "--screenshot-delay", "15",
        "--screen-root", monitor,
        "--silent",
        "--disable-mouse",
        "--disable-parallax",
    ]
    if assets_dir and os.path.exists(assets_dir):
        cmd += ["--assets-dir", assets_dir]
    cmd.append(wp_dir)

    if os.path.exists(output_path):
        os.remove(output_path)

    proc = subprocess.Popen(
        cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
    )

    waited = 0.0
    while waited < timeout:
        if os.path.exists(output_path) and os.path.getsize(output_path) > 0:
            time.sleep(0.5)
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
            return True

        poll = proc.poll()
        if poll is not None and poll != 0:
            _, err = proc.communicate(timeout=2)
            print(f"[WPE] --screenshot failed (exit {poll}): {err.strip()}", file=sys.stderr)
            break
        time.sleep(0.3)
        waited += 0.3
    else:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()

    # Method 2: grim capture — WPE already running this wallpaper
    if is_wpe_running_for(wp_dir):
        notify("Using grim", f"Capturing via grim on {monitor}")
        if capture_with_grim(monitor, output_path):
            return True

    # Method 3: launch WPE in full-res window + grim the window region
    mw, mh = get_monitor_resolution(monitor)
    notify("Rendering window", f"Full-res capture at {mw}x{mh}")

    win_args = [
        "linux-wallpaperengine",
        "--window", f"0x0x{mw}x{mh}",
        "--silent",
    ]
    if assets_dir and os.path.exists(assets_dir):
        win_args += ["--assets-dir", assets_dir]
    win_args.append(wp_dir)

    win_proc = subprocess.Popen(
        win_args, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
    )

    win_geom = None
    for i in range(40):
        poll = win_proc.poll()
        if poll is not None:
            _, err = win_proc.communicate(timeout=2)
            print(f"[WPE] --window mode crashed (exit {poll}): {err.strip()}", file=sys.stderr)
            break

        time.sleep(0.25)
        try:
            clients = subprocess.run(
                ["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=3
            )
            for c in json.loads(clients.stdout):
                if "wallpaperengine" in (c.get("title", "") or "").lower():
                    at = c.get("at", [0, 0])
                    size = c.get("size", [0, 0])
                    if at and size and size[0] > 100 and size[1] > 100:
                        win_geom = f"{at[0]},{at[1]} {size[0]}x{size[1]}"
                        break
        except Exception:
            pass
        if win_geom:
            break

    if win_geom:
        time.sleep(3)
        subprocess.run(["grim", "-g", win_geom, output_path], capture_output=True, timeout=15)

    win_proc.terminate()
    try:
        win_proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        win_proc.kill()
        win_proc.wait()

    if os.path.exists(output_path) and os.path.getsize(output_path) > 0:
        return True

    return False


def download_wallpaper(wp_id, dest_dir, quality="preview"):
    wp_dir = find_wallpaper_dir(wp_id)
    if not wp_dir:
        notify("Download failed", f"Wallpaper {wp_id} not found on disk.", "critical")
        return False

    project_json_path = os.path.join(wp_dir, "project.json")
    with open(project_json_path, "r") as f:
        data = json.load(f)

    title = data.get("title", f"Wallpaper_{wp_id}")
    wp_type = data.get("type", "NONE")
    file_ref = data.get("file", "")
    preview = data.get("preview", "")
    dependency = data.get("dependency", "")

    safe_title = sanitize_filename(title)
    os.makedirs(dest_dir, exist_ok=True)

    # If this is a preset/dependency, resolve the base wallpaper
    if wp_type == "NONE" and dependency:
        notify("Resolving dependency...", f"Preset '{title}' depends on {dependency}")
        return download_wallpaper(dependency, dest_dir, quality)

    downloaded_files = []

    # --- Video wallpapers: copy the actual video file ---
    if wp_type.lower() == "video" and file_ref:
        src = os.path.join(wp_dir, file_ref)
        if os.path.exists(src):
            ext = os.path.splitext(file_ref)[1]
            dest = os.path.join(dest_dir, f"{safe_title}{ext}")
            if os.path.exists(dest) and os.path.getsize(dest) == os.path.getsize(src):
                notify("Already downloaded", f"'{title}' is already in your wallpapers folder.")
                return True
            shutil.copy2(src, dest)
            notify("Downloaded!", f"Video saved: {safe_title}{ext}")
            return True
        else:
            notify("Download failed", f"Video file not found: {file_ref}", "critical")
            return False

    # --- Web wallpapers ---
    if wp_type.lower() == "web":
        if quality == "full":
            dest_subdir = os.path.join(dest_dir, safe_title)
            if os.path.exists(dest_subdir):
                shutil.rmtree(dest_subdir)
            shutil.copytree(
                wp_dir, dest_subdir,
                ignore=shutil.ignore_patterns("project.json"),
            )
            notify("Downloaded!", f"Web project saved: {safe_title}")
            return True
        else:
            video_exts = ('.mp4', '.webm', '.avi', '.mov')
            for fname in os.listdir(wp_dir):
                if fname.lower().endswith(video_exts):
                    src = os.path.join(wp_dir, fname)
                    dest = os.path.join(dest_dir, f"{safe_title}_{fname}")
                    if not os.path.exists(dest) or os.path.getsize(dest) != os.path.getsize(src):
                        shutil.copy2(src, dest)
                    downloaded_files.append(dest)
            if downloaded_files:
                notify("Downloaded!", f"Web assets saved: {safe_title} ({len(downloaded_files)} files)")
                return True

    # --- Scene wallpapers ---
    if wp_type.lower() == "scene":
        if quality == "full":
            assets_dir = find_assets_dir()
            screenshot_path = os.path.join(dest_dir, f"{safe_title}.png")

            notify("Rendering scene...", f"'{title}': capturing screenshot via linux-wallpaperengine")
            if render_scene_screenshot(wp_id, wp_dir, assets_dir, screenshot_path):
                size_kb = os.path.getsize(screenshot_path) // 1024
                notify("Downloaded!", f"Scene rendered: {safe_title}.png ({size_kb}KB)")
                return True
            else:
                notify("Screenshot failed", f"Falling back to preview for '{title}'", "normal")

        if preview:
            preview_path = os.path.join(wp_dir, preview)
            if os.path.exists(preview_path):
                ext = os.path.splitext(preview)[1]
                dest = os.path.join(dest_dir, f"{safe_title}{ext}")
                shutil.copy2(preview_path, dest)

                if ext.lower() == '.gif':
                    try:
                        png_dest = os.path.join(dest_dir, f"{safe_title}.png")
                        subprocess.run(
                            ["ffmpeg", "-y", "-i", preview_path, "-vframes", "1", png_dest],
                            capture_output=True, timeout=10,
                        )
                    except Exception:
                        pass

                notify("Downloaded!", f"Preview saved: {safe_title}{ext}")
                return True

    # --- Preset/other with full quality: copy all non-metadata files ---
    if quality == "full":
        extra_files = []
        for fname in os.listdir(wp_dir):
            if fname in ("project.json", "preview.jpg", "preview.gif", "preview.png", "scene.pkg", "gifscene.pkg"):
                continue
            if fname == os.path.basename(file_ref) if file_ref else False:
                continue
            src = os.path.join(wp_dir, fname)
            if os.path.isfile(src):
                dest = os.path.join(dest_dir, f"{safe_title}_{fname}")
                shutil.copy2(src, dest)
                extra_files.append(dest)
            elif os.path.isdir(src):
                dest = os.path.join(dest_dir, f"{safe_title}_{fname}")
                if os.path.exists(dest):
                    shutil.rmtree(dest)
                shutil.copytree(src, dest)
                extra_files.append(dest)
        if extra_files:
            notify("Downloaded!", f"Assets saved: {safe_title} ({len(extra_files)} files)")
            return True

    # If we got here, nothing was downloadable
    notify("Download failed", f"No downloadable content found for '{title}' (type: {wp_type})", "critical")
    return False


def main():
    parser = argparse.ArgumentParser(description="Download a WPE wallpaper to ~/Pictures/Wallpapers/")
    parser.add_argument("workshop_id", help="Steam Workshop ID of the wallpaper")
    parser.add_argument("--dest", default=os.path.expanduser("~/Pictures/Wallpapers"),
                        help="Destination directory (default: ~/Pictures/Wallpapers)")
    parser.add_argument("--quality", choices=["preview", "full"], default="preview",
                        help="Quality mode (default: preview)")
    args = parser.parse_args()

    success = download_wallpaper(args.workshop_id, args.dest, args.quality)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
