#!/usr/bin/env python3
"""
Analyze COLMAP database to understand matching between W and Z images.
"""

import sys
import os
import sqlite3
from collections import defaultdict


def analyze_database(db_path):
    """Analyze a COLMAP database to understand matching patterns."""

    if not os.path.exists(db_path):
        print(f"ERROR: Database not found: {db_path}")
        return

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Get images
    cursor.execute("SELECT image_id, name FROM images")
    images = {row[0]: row[1] for row in cursor.fetchall()}

    print(f"\n=== COLMAP Database Analysis ===")
    print(f"Database: {db_path}")
    print(f"Total images: {len(images)}")

    # Categorize images
    w_images = {k: v for k, v in images.items() if 'video_W' in v}
    z_images = {k: v for k, v in images.items() if 'video_Z' in v}

    print(f"W images: {len(w_images)}")
    print(f"Z images: {len(z_images)}")

    # Get two-view geometries (matches that passed geometric verification)
    cursor.execute("""
        SELECT pair_id, rows, cols, data
        FROM two_view_geometries
        WHERE rows > 0
    """)
    geometries = cursor.fetchall()

    print(f"\nTwo-view geometries (verified matches): {len(geometries)}")

    # Analyze match types
    ww_matches = []  # W-W matches
    zz_matches = []  # Z-Z matches
    wz_matches = []  # W-Z cross-camera matches

    for pair_id, rows, cols, data in geometries:
        # Decode pair_id (COLMAP uses a specific encoding)
        # pair_id = image_id1 * 2147483647 + image_id2 where image_id1 < image_id2
        image_id1 = pair_id // 2147483647
        image_id2 = pair_id % 2147483647

        if image_id1 not in images or image_id2 not in images:
            continue

        name1 = images[image_id1]
        name2 = images[image_id2]

        is_w1 = 'video_W' in name1
        is_w2 = 'video_W' in name2

        num_matches = rows

        if is_w1 and is_w2:
            ww_matches.append((name1, name2, num_matches))
        elif not is_w1 and not is_w2:
            zz_matches.append((name1, name2, num_matches))
        else:
            wz_matches.append((name1, name2, num_matches))

    print(f"\nMatch breakdown:")
    print(f"  W-W (same camera): {len(ww_matches)} pairs")
    print(f"  Z-Z (same camera): {len(zz_matches)} pairs")
    print(f"  W-Z (cross-camera): {len(wz_matches)} pairs")

    # Statistics
    if ww_matches:
        ww_avg = sum(m[2] for m in ww_matches) / len(ww_matches)
        print(f"\n  W-W average matches: {ww_avg:.1f}")
        top_ww = sorted(ww_matches, key=lambda x: x[2], reverse=True)[:5]
        print(f"  Top W-W matches:")
        for n1, n2, count in top_ww:
            print(f"    {os.path.basename(n1)} <-> {os.path.basename(n2)}: {count}")

    if zz_matches:
        zz_avg = sum(m[2] for m in zz_matches) / len(zz_matches)
        print(f"\n  Z-Z average matches: {zz_avg:.1f}")
        top_zz = sorted(zz_matches, key=lambda x: x[2], reverse=True)[:5]
        print(f"  Top Z-Z matches:")
        for n1, n2, count in top_zz:
            print(f"    {os.path.basename(n1)} <-> {os.path.basename(n2)}: {count}")

    if wz_matches:
        wz_avg = sum(m[2] for m in wz_matches) / len(wz_matches)
        print(f"\n  W-Z average matches: {wz_avg:.1f}")
        top_wz = sorted(wz_matches, key=lambda x: x[2], reverse=True)[:5]
        print(f"  Top W-Z matches:")
        for n1, n2, count in top_wz:
            print(f"    {os.path.basename(n1)} <-> {os.path.basename(n2)}: {count}")
    else:
        print(f"\n  WARNING: No W-Z cross-camera matches found!")
        print(f"  This explains why Z images are not being registered.")

    conn.close()


def main():
    if len(sys.argv) < 2:
        print("Usage: python analyze_matches.py <database_path>")
        sys.exit(1)

    db_path = sys.argv[1]
    analyze_database(db_path)


if __name__ == "__main__":
    main()
