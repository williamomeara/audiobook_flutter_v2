#!/usr/bin/env python3
"""
Build the complete Supertonic release archive.

This script downloads all required files from HuggingFace and packages them
into a tar.gz archive suitable for the audiobook_flutter_assets release.

Expected output structure (inside supertonic/):
  onnx/
    text_encoder.onnx
    duration_predictor.onnx
    vector_estimator.onnx
    vocoder.onnx
    unicode_indexer.json
    tts.json
  voice_styles/
    M1.json, M2.json, M3.json, M4.json, M5.json
    F1.json, F2.json, F3.json, F4.json, F5.json

Usage:
    python scripts/build_supertonic_release.py [--output supertonic_core.tar.gz]
"""

import argparse
import os
import sys
import shutil
import tarfile
import urllib.request
import urllib.error

# HuggingFace base URL
HF_BASE = "https://huggingface.co/Supertone/supertonic/resolve/main/"

# Required ONNX model files
ONNX_FILES = [
    "onnx/text_encoder.onnx",
    "onnx/duration_predictor.onnx",
    "onnx/vector_estimator.onnx",
    "onnx/vocoder.onnx",
    "onnx/unicode_indexer.json",
    "onnx/tts.json",
]

# Voice style files
VOICE_STYLES = [
    "voice_styles/M1.json",
    "voice_styles/M2.json",
    "voice_styles/M3.json",
    "voice_styles/M4.json",
    "voice_styles/M5.json",
    "voice_styles/F1.json",
    "voice_styles/F2.json",
    "voice_styles/F3.json",
    "voice_styles/F4.json",
    "voice_styles/F5.json",
]

ALL_FILES = ONNX_FILES + VOICE_STYLES


def download_file(url: str, dest: str, force: bool = False) -> bool:
    """Download a file from URL to destination."""
    if os.path.exists(dest) and not force:
        print(f"  Skipping (exists): {dest}")
        return True
    
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    
    print(f"  Downloading: {url}")
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req) as resp:
            total = int(resp.headers.get('content-length', 0))
            downloaded = 0
            
            with open(dest + ".tmp", "wb") as out:
                while True:
                    chunk = resp.read(1024 * 1024)  # 1MB chunks
                    if not chunk:
                        break
                    out.write(chunk)
                    downloaded += len(chunk)
                    if total > 0:
                        pct = (downloaded / total) * 100
                        print(f"    {downloaded:,} / {total:,} bytes ({pct:.1f}%)", end='\r')
        
        os.replace(dest + ".tmp", dest)
        print(f"    Done: {dest}")
        return True
        
    except urllib.error.HTTPError as e:
        print(f"    ERROR: {e}")
        if os.path.exists(dest + ".tmp"):
            os.remove(dest + ".tmp")
        return False


def create_archive(source_dir: str, output_path: str) -> bool:
    """Create a tar.gz archive from source directory."""
    print(f"\nCreating archive: {output_path}")
    try:
        with tarfile.open(output_path, "w:gz") as tar:
            # Add the supertonic directory
            tar.add(source_dir, arcname="supertonic")
        
        size_mb = os.path.getsize(output_path) / (1024 * 1024)
        print(f"  Archive created: {size_mb:.1f} MB")
        return True
    except Exception as e:
        print(f"  ERROR creating archive: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(description="Build Supertonic release archive")
    parser.add_argument("--output", default="supertonic_core.tar.gz",
                        help="Output archive path (default: supertonic_core.tar.gz)")
    parser.add_argument("--work-dir", default="/tmp/supertonic_build",
                        help="Working directory for downloads")
    parser.add_argument("--force", action="store_true",
                        help="Force re-download of all files")
    parser.add_argument("--keep", action="store_true",
                        help="Keep working directory after completion")
    args = parser.parse_args()
    
    work_dir = args.work_dir
    supertonic_dir = os.path.join(work_dir, "supertonic")
    
    print("=" * 60)
    print("Supertonic Release Archive Builder")
    print("=" * 60)
    print(f"Work directory: {work_dir}")
    print(f"Output: {args.output}")
    print()
    
    # Create work directory
    os.makedirs(supertonic_dir, exist_ok=True)
    
    # Download all files
    print("Downloading files from HuggingFace...")
    failed = []
    for file_path in ALL_FILES:
        url = HF_BASE + file_path
        dest = os.path.join(supertonic_dir, file_path)
        if not download_file(url, dest, args.force):
            failed.append(file_path)
    
    if failed:
        print(f"\nERROR: Failed to download {len(failed)} files:")
        for f in failed:
            print(f"  - {f}")
        return 1
    
    print(f"\nAll {len(ALL_FILES)} files downloaded successfully!")
    
    # Create archive
    if not create_archive(supertonic_dir, args.output):
        return 2
    
    # Cleanup
    if not args.keep:
        print(f"\nCleaning up: {work_dir}")
        shutil.rmtree(work_dir)
    else:
        print(f"\nWork directory kept: {work_dir}")
    
    print("\n" + "=" * 60)
    print("SUCCESS!")
    print(f"Upload {args.output} to GitHub releases:")
    print("  gh release upload ai-cores-int8-v1 supertonic_core.tar.gz --clobber")
    print("=" * 60)
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
