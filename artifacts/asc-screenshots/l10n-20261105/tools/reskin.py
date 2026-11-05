#!/usr/bin/env python3
"""Replace captures and CoreText headers in finished screenshot frames."""
from __future__ import annotations

import argparse
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

from common import config, destinations, erase_header, headline, paste_screen, raw_path, read_json, source


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--config', type=Path, required=True)
    p.add_argument('--raw-root', type=Path, required=True)
    p.add_argument('--headers', type=Path, required=True)
    p.add_argument('--locale', required=True)
    p.add_argument('--out', type=Path, required=True, help='output root; writes ROOT/LOCALE/SET/file.png')
    p.add_argument('--set', dest='set_key')
    args = p.parse_args()
    data, headers = config(args.config), read_json(args.headers)[args.locale]
    sets = data['sets'] if args.set_key is None else {args.set_key: data['sets'][args.set_key]}
    plans = []
    temp_dir = tempfile.TemporaryDirectory(prefix=f'reskin-{args.locale}-')
    temp_root = Path(temp_dir.name)
    for key, group in sets.items():
        frames = group['frames']
        jobs = []
        placements = []
        for frame in frames:
            text = headers.get(frame['file'], '')
            if not text.strip():
                raise ValueError(f"{frame['file']}: missing header text")
            frame_jobs = []
            line_styles = frame.get('header_lines')
            if line_styles:
                lines = text.split('\n')
                if len(lines) != len(line_styles):
                    raise ValueError(f"{frame['file']}: expected {len(line_styles)} header lines, found {len(lines)}")
                for index, (line, style) in enumerate(zip(lines, line_styles)):
                    frame_jobs.append(add_job(jobs, line, style, args.locale, f'header-{index + 1}'))
            else:
                frame_jobs.append(add_job(jobs, text, frame, args.locale, 'header'))
            for extra in frame.get('extra_text', []):
                extra_key = f"{frame['file']}#{extra['key']}"
                extra_text = headers.get(extra_key, '')
                if not extra_text.strip():
                    raise ValueError(f"{extra_key}: missing localized text")
                frame_jobs.append(add_job(jobs, extra_text, extra, args.locale, f"extra-{extra['key']}"))
            placements.append((frame, frame_jobs))
            for target in destinations(frame):
                if not raw_path(args.raw_root, args.locale, key, target['raw']).is_file():
                    raise ValueError(f"missing raw {key}/{target['raw']}")
        results = headline(jobs)
        sizes = {}
        for job, result in zip(jobs, results):
            minimum = job['minSize']
            if not result['fits'] or result['size'] < minimum:
                raise ValueError(f"{key}: {job['role']} text does not fit; minimum={minimum:g} text={job['text']!r}")
            sizes[job['role']] = min(sizes.get(job['role'], result['size']), result['size'])
        for job in jobs:
            job['size'] = sizes[job['role']]
        with_outputs = []
        for index, (frame, frame_jobs) in enumerate(placements):
            for line_index, job in enumerate(frame_jobs):
                job['out'] = str(temp_root / f'{key}-{index}-{line_index}.png')
            with_outputs.append((frame, frame_jobs))
        rendered = headline(jobs)
        if not all(result['fits'] for result in rendered):
            raise ValueError(f"{key}: shared header size does not fit")
        plans.append((key, group, with_outputs))
    for key, group, placements in plans:
        frames = group['frames']
        output = args.out / args.locale / key
        output.mkdir(parents=True, exist_ok=True)
        for frame, frame_jobs in placements:
            with Image.open(source(data, frame['base'])) as im:
                canvas = im.convert('RGB')
            if canvas.size != tuple(group['canvas']):
                raise ValueError(f"{frame['file']}: base size differs from canvas")
            plate = None
            if frame.get('plate'):
                with Image.open(source(data, frame['plate'])) as im:
                    plate = im.convert('RGB')
            erase_header(canvas, frame['header_box'], plate)
            for target in destinations(frame):
                with Image.open(raw_path(args.raw_root, args.locale, key, target['raw'])) as raw:
                    paste_screen(canvas, raw, target['rect'], target.get('radius', 0))
            for extra in frame.get('extra_text', []):
                if 'fill_color' not in extra:
                    continue
                x, y, width, height = extra['box']
                radius = extra.get('fill_radius', height / 2)
                ImageDraw.Draw(canvas).rounded_rectangle(
                    (x, y, x + width - 1, y + height - 1), radius=radius,
                    fill=tuple(extra['fill_color']),
                )
            for job in frame_jobs:
                x, y = job['origin']
                with Image.open(job['out']) as overlay:
                    canvas.paste(overlay, (x, y), overlay)
            canvas.save(output / frame['file'], format='PNG', optimize=True)
        sizes = [job['size'] for _, frame_jobs in placements for job in frame_jobs]
        size_summary = ','.join(format(size, 'g') for size in sizes)
        print(f'{args.locale}/{key}: {len(frames)} frames sizes={size_summary}')
    temp_dir.cleanup()


def add_job(jobs: list[dict], text: str, style: dict, locale: str, role: str) -> dict:
    box = style['box'] if 'box' in style else style['header_box']
    if len(box) == 4:
        origin, size = box[:2], box[2:]
    else:
        origin, size = [0, 0], box
    job = {
        'text': text,
        'locale': locale,
        'font': style['font'],
        'color': style['color'],
        'box': size,
        'maxSize': style.get('max_size', 200),
        'minSize': style.get('min_size', 1),
        'align': style.get('align', 'left'),
        'role': role,
        'origin': origin,
    }
    jobs.append(job)
    return job


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError) as error:
        print(f'reskin: {error}', file=sys.stderr)
        sys.exit(1)
