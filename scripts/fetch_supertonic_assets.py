#!/usr/bin/env python3
"""
Simple asset fetcher for Supertonic voice models.

Behavior:
 - If SUPERSONIC_RELEASE_URL is set and --skip-release is not given, download that archive and extract.
 - Otherwise, attempt per-file downloads from a Hugging Face repository/base URL.

Supported args:
  --revision    revision string used when building HF URLs (default: main)
  --style       comma-separated list of voice style names to fetch (default: all listed in manifest)
  --dest        destination directory (default: assets/supertonic)
  --force       overwrite existing files
  --skip-release skip trying the release archive

Environment variables:
  HF_TOKEN or HUGGINGFACE_TOKEN  - token for authenticated Hugging Face downloads (optional)
  SUPERSONIC_RELEASE_URL - direct archive URL (optional)
  SUPERTONIC_HF_BASE - base URL for HF file resolves. If not set the script will assume
                       https://huggingface.co/supertonic/supertonic/resolve/{revision}/

This is intentionally small and dependency-free (uses urllib).
"""

import argparse
import os
import sys
import shutil
import tempfile
import json
import zipfile
import tarfile
import urllib.request
import urllib.error
from urllib.parse import urljoin

REQUIRED_ONNX = [
    "duration_predictor.onnx",
    "text_encoder.onnx",
    "vector_estimator.onnx",
    "vocoder.onnx",
]
REQUIRED_JSON = [
    "tts.json",
    "unicode_indexer.json",
]
VOICE_STYLES_DIRNAME = "voice_styles"
ONNX_DIRNAME = "onnx"


def download_url(url, dest_path, token=None, force=False):
    if os.path.exists(dest_path) and not force:
        print(f"Skipping existing: {dest_path}")
        return dest_path
    os.makedirs(os.path.dirname(dest_path), exist_ok=True)
    headers = {}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req) as resp, open(dest_path + ".part", "wb") as out:
            shutil.copyfileobj(resp, out)
        os.replace(dest_path + ".part", dest_path)
        print(f"Downloaded: {url} -> {dest_path}")
        return dest_path
    except urllib.error.HTTPError as e:
        if os.path.exists(dest_path + ".part"):
            os.remove(dest_path + ".part")
        raise


def extract_archive(archive_path, dest_dir, force=False):
    print(f"Extracting {archive_path} -> {dest_dir}")
    if archive_path.endswith('.zip'):
        with zipfile.ZipFile(archive_path, 'r') as z:
            for member in z.namelist():
                target = os.path.join(dest_dir, member)
                if os.path.exists(target) and not force:
                    # skip
                    continue
                # Ensure parent exists
                parent = os.path.dirname(target)
                if parent:
                    os.makedirs(parent, exist_ok=True)
            z.extractall(dest_dir)
    elif archive_path.endswith(('.tar.gz', '.tgz', '.tar')):
        with tarfile.open(archive_path, 'r:*') as t:
            t.extractall(dest_dir)
    else:
        raise RuntimeError('Unsupported archive type: ' + archive_path)


def try_download_release_and_extract(url, dest, token=None, force=False):
    # download to a temp file then extract
    tmp = tempfile.mkdtemp(prefix='supertonic_release_')
    try:
        filename = os.path.join(tmp, os.path.basename(url.split('?')[0]) or 'release.zip')
        download_url(url, filename, token=token, force=True)
        extract_archive(filename, dest, force=force)
        return True
    except Exception as e:
        print(f"Release download failed: {e}")
        return False
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def download_per_file(hf_base, revision, dest, styles=None, token=None, force=False):
    # hf_base should be something like https://huggingface.co/USER/REPO/resolve/{revision}/
    # The script will fetch ONNX and JSONs into dest/onnx and voice styles into dest/voice_styles
    onnx_dir = os.path.join(dest, ONNX_DIRNAME)
    styles_dir = os.path.join(dest, VOICE_STYLES_DIRNAME)
    os.makedirs(onnx_dir, exist_ok=True)
    os.makedirs(styles_dir, exist_ok=True)

    # Download required ONNX
    for fname in REQUIRED_ONNX:
        url = hf_base.format(revision=revision) + 'onnx/' + fname
        target = os.path.join(onnx_dir, fname)
        download_url(url, target, token=token, force=force)

    # Download required JSONs
    for fname in REQUIRED_JSON:
        url = hf_base.format(revision=revision) + 'onnx/' + fname
        target = os.path.join(onnx_dir, fname)
        download_url(url, target, token=token, force=force)

    # Download voice style JSONs (M1-M5, F1-F5)
    default_styles = ['M1', 'M2', 'M3', 'M4', 'M5', 'F1', 'F2', 'F3', 'F4', 'F5']
    if styles is not None:
        requested = [s.strip() for s in styles.split(',') if s.strip()]
    else:
        requested = default_styles

    for style in requested:
        # Voice styles are JSON files directly in voice_styles/
        url = hf_base.format(revision=revision) + f'voice_styles/{style}.json'
        target = os.path.join(styles_dir, f'{style}.json')
        try:
            download_url(url, target, token=token, force=force)
        except Exception as e:
            print(f"Warning: Could not download voice style {style}: {e}")

    print("Per-file downloads finished.")


def main(argv):
    parser = argparse.ArgumentParser(description='Fetch Supertonic assets (basic).')
    parser.add_argument('--revision', default='main', help='Revision / branch / tag to fetch from (default: main)')
    parser.add_argument('--style', default=None, help='Comma-separated voice styles to download (default: none)')
    parser.add_argument('--dest', default='assets/supertonic', help='Destination directory (default: assets/supertonic)')
    parser.add_argument('--force', action='store_true', help='Overwrite existing files')
    parser.add_argument('--skip-release', action='store_true', help='Skip attempting release archive download')
    parser.add_argument('--supertonic-release-url', default=None, help='Direct release archive URL (overrides SUPERSONIC_RELEASE_URL env)')
    args = parser.parse_args(argv)

    dest = args.dest
    os.makedirs(dest, exist_ok=True)

    env_token = os.environ.get('HF_TOKEN') or os.environ.get('HUGGINGFACE_TOKEN')
    env_release = os.environ.get('SUPERSONIC_RELEASE_URL', 'https://github.com/williamomeara/audiobook_flutter_assets/releases/download/ai-cores-int8-v1/supertonic_core.tar.gz')
    hf_base_env = os.environ.get('SUPERTONIC_HF_BASE')

    release_url = args.supertonic_release_url or env_release

    if release_url and not args.skip_release:
        print('Attempting to download release archive...')
        ok = try_download_release_and_extract(release_url, dest, token=env_token, force=args.force)
        if ok:
            print('Release archive fetched and extracted.')
            return 0
        else:
            print('Release fetch failed, falling back to per-file HF downloads.')

    # Build a HF base URL
    if hf_base_env:
        hf_base = hf_base_env
    else:
        # default repo path; user can override SUPERTONIC_HF_BASE
        # This default assumes a repo path; change if needed.
        hf_base = 'https://huggingface.co/Supertone/supertonic/resolve/{revision}/'
    if '{revision}' not in hf_base:
        if not hf_base.endswith('/'):
            hf_base += '/'
        hf_base += '{revision}/'

    # Ensure hf_base is a format string
    try:
        hf_base.format(revision=args.revision)
    except Exception as e:
        print('Invalid SUPERTONIC_HF_BASE value:', hf_base)
        return 2

    try:
        download_per_file(hf_base, args.revision, dest, styles=args.style, token=env_token, force=args.force)
    except Exception as e:
        print('Per-file download failed:', e)
        return 3

    print('All done. Assets placed in', dest)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
