#!/usr/bin/env python
# -*- coding: utf-8 -*-
# v1.0.0 - Consolida fotos con inventario SQLite, hash exacto y revisión visual.
from __future__ import print_function

import argparse
import hashlib
import os
import shutil
import sqlite3
import subprocess
import sys

VERSION = 'v1.0.0'
IMAGE_EXTENSIONS = set((
    '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tif', '.tiff', '.webp',
    '.heic', '.heif', '.avif', '.ppm', '.pgm', '.pbm', '.pnm', '.dng',
    '.cr2', '.cr3', '.nef', '.arw', '.orf', '.rw2', '.raf', '.pef',
    '.srw', '.3fr', '.iiq', '.kdc', '.dcr', '.mef', '.mos', '.mrw',
    '.nrw', '.rwl', '.x3f'
))
DHASH_DISTANCE_LIMIT = 4
CHUNK_BITS = (13, 13, 13, 13, 12)


class DedupeError(Exception):
    pass


def absolute(path):
    return os.path.realpath(os.path.abspath(path))


def is_within(path, root):
    try:
        return os.path.commonpath((path, root)) == root
    except AttributeError:
        path = path.rstrip(os.sep) + os.sep
        root = root.rstrip(os.sep) + os.sep
        return path.startswith(root)


def check_roots(source_a, source_b, destination, must_exist=True):
    raw_roots = [os.path.abspath(source_a), os.path.abspath(source_b),
                 os.path.abspath(destination)]
    for label, path in zip(('A', 'B', 'C'), raw_roots):
        if os.path.islink(path):
            raise DedupeError('No se aceptan carpetas raíz que sean enlaces simbólicos: %s' % label)
    roots = [absolute(source_a), absolute(source_b), absolute(destination)]
    a, b, dest = roots
    if a == b or is_within(a, b) or is_within(b, a):
        raise DedupeError('A y B deben ser carpetas distintas y no anidadas.')
    if any(is_within(dest, root) or is_within(root, dest) for root in (a, b)):
        raise DedupeError('C no puede estar dentro de A/B ni contener A/B.')
    for label, path in zip(('A', 'B'), (a, b)):
        if must_exist and not os.path.isdir(path):
            raise DedupeError('No existe la carpeta %s: %s' % (label, path))
    return roots


def default_db(destination):
    return os.path.join(destination, '.photo-dedupe.sqlite3')


def connect_db(path):
    conn = sqlite3.connect(path)
    conn.execute('PRAGMA foreign_keys = ON')
    conn.execute('''CREATE TABLE IF NOT EXISTS metadata (
        key TEXT PRIMARY KEY, value TEXT NOT NULL)''')
    conn.execute('''CREATE TABLE IF NOT EXISTS files (
        root_index INTEGER NOT NULL,
        relpath TEXT NOT NULL,
        size INTEGER NOT NULL,
        mtime REAL NOT NULL,
        sha256 TEXT,
        dhash TEXT,
        state TEXT NOT NULL,
        dest_path TEXT,
        canonical_sha TEXT,
        error TEXT,
        source_deleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (root_index, relpath))''')
    conn.execute('''CREATE TABLE IF NOT EXISTS candidates (
        candidate_id INTEGER PRIMARY KEY AUTOINCREMENT,
        sha_a TEXT NOT NULL,
        sha_b TEXT NOT NULL,
        distance INTEGER NOT NULL,
        decision TEXT NOT NULL DEFAULT 'pending',
        active INTEGER NOT NULL DEFAULT 1,
        UNIQUE (sha_a, sha_b))''')
    conn.execute('''CREATE TABLE IF NOT EXISTS issues (
        root_index INTEGER NOT NULL,
        relpath TEXT NOT NULL,
        detail TEXT NOT NULL,
        active INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY (root_index, relpath))''')
    conn.commit()
    return conn


def get_meta(conn, key):
    row = conn.execute('SELECT value FROM metadata WHERE key = ?', (key,)).fetchone()
    return row[0] if row else None


def set_meta(conn, key, value):
    conn.execute('INSERT OR REPLACE INTO metadata(key, value) VALUES (?, ?)',
                 (key, str(value)))


def set_roots(conn, roots):
    keys = ('source_a', 'source_b', 'destination')
    for key, value in zip(keys, roots):
        old = get_meta(conn, key)
        if old and old != value:
            raise DedupeError('La base ya está asociada a otra ruta (%s). Usa su base original.' % key)
        set_meta(conn, key, value)
    set_meta(conn, 'schema_version', '1')
    conn.commit()


def ensure_db_roots(conn, roots):
    keys = ('source_a', 'source_b', 'destination')
    for key, value in zip(keys, roots):
        if get_meta(conn, key) != value:
            raise DedupeError('Las rutas no coinciden con las guardadas en SQLite (%s).' % key)


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as handle:
        while True:
            block = handle.read(1024 * 1024)
            if not block:
                break
            digest.update(block)
    return digest.hexdigest()


def visual_hash(path, ffmpeg):
    command = [ffmpeg, '-v', 'error', '-i', path, '-vf',
               'scale=9:8:flags=area,format=gray', '-frames:v', '1',
               '-f', 'rawvideo', '-pix_fmt', 'gray', 'pipe:1']
    try:
        pixels = subprocess.check_output(command, stderr=subprocess.PIPE)
    except (OSError, subprocess.CalledProcessError) as exc:
        detail = getattr(exc, 'output', '')
        if not detail:
            detail = str(exc)
        raise DedupeError('FFmpeg no pudo leer la imagen: %s' % detail)
    if len(pixels) != 72:
        raise DedupeError('FFmpeg devolvió %d bytes de imagen; se esperaban 72.' % len(pixels))
    def pixel_value(value):
        return value if isinstance(value, int) else ord(value)
    value = 0
    bit = 63
    for row in range(8):
        for col in range(8):
            if pixel_value(pixels[row * 9 + col]) > pixel_value(pixels[row * 9 + col + 1]):
                value |= (1 << bit)
            bit -= 1
    return '%016x' % value


def walk_sources(roots):
    records = []
    issues = []
    for root_index, root in enumerate(roots[:2]):
        def onerror(exc):
            issues.append((root_index, getattr(exc, 'filename', '') or '.',
                           'No se pudo leer la carpeta: %s' % exc))

        for current, directories, filenames in os.walk(root, topdown=True,
                                                        followlinks=False,
                                                        onerror=onerror):
            for dirname in list(directories):
                full = os.path.join(current, dirname)
                if os.path.islink(full):
                    issues.append((root_index, os.path.relpath(full, root),
                                   'Directorio simbólico no procesado'))
                    directories.remove(dirname)
            for filename in filenames:
                full = os.path.join(current, filename)
                relpath = os.path.relpath(full, root)
                if os.path.islink(full) or not os.path.isfile(full):
                    issues.append((root_index, relpath,
                                   'No es un archivo regular; no se procesará'))
                    continue
                if os.path.splitext(filename)[1].lower() not in IMAGE_EXTENSIONS:
                    issues.append((root_index, relpath,
                                   'Extensión no reconocida como foto'))
                    continue
                try:
                    info = os.stat(full)
                    records.append((root_index, relpath, info.st_size, info.st_mtime, full))
                except OSError as exc:
                    issues.append((root_index, relpath, 'No se pudo inspeccionar: %s' % exc))
    records.sort(key=lambda row: (row[0], row[1]))
    return records, issues


def add_inventory(conn, roots, records, issues, need_visual, ffmpeg):
    conn.execute('UPDATE files SET state = CASE WHEN source_deleted = 1 THEN state ELSE "missing" END')
    for index, row in enumerate(records, 1):
        root_index, relpath, size, mtime, full = row
        old = conn.execute('''SELECT size, mtime, sha256, dhash, state, dest_path,
                              canonical_sha, source_deleted
                              FROM files WHERE root_index = ? AND relpath = ?''',
                           (root_index, relpath)).fetchone()
        try:
            digest = sha256_file(full)
            visual = (old[3] if need_visual and old and old[2] == digest and old[3]
                      else visual_hash(full, ffmpeg) if need_visual else None)
            if old and old[2] == digest:
                state = old[4] if old[4] not in ('missing', 'error') else 'scanned'
                dest_path = old[5]
                canonical_sha = old[6]
                deleted = old[7]
            else:
                state, dest_path, canonical_sha, deleted = 'scanned', None, None, 0
            conn.execute('''INSERT OR REPLACE INTO files
                (root_index, relpath, size, mtime, sha256, dhash, state,
                 dest_path, canonical_sha, error, source_deleted)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?)''',
                (root_index, relpath, size, mtime, digest, visual, state,
                 dest_path, canonical_sha, deleted))
        except (IOError, OSError, DedupeError) as exc:
            conn.execute('''INSERT OR REPLACE INTO files
                (root_index, relpath, size, mtime, sha256, dhash, state,
                 dest_path, canonical_sha, error, source_deleted)
                VALUES (?, ?, ?, ?, NULL, NULL, 'error', NULL, NULL, ?, 0)''',
                (root_index, relpath, size, mtime, str(exc)))
        conn.commit()
        if index % 100 == 0 or index == len(records):
            print('Inventariadas %d/%d fotos.' % (index, len(records)))
    conn.execute('UPDATE issues SET active = 0')
    for root_index, relpath, detail in issues:
        conn.execute('''INSERT OR REPLACE INTO issues(root_index, relpath, detail, active)
            VALUES (?, ?, ?, 1)''', (root_index, relpath, detail))
    conn.commit()
    return issues


def unique_hash_rows(conn):
    rows = conn.execute('''SELECT f.root_index, f.relpath, f.sha256, f.dhash, f.state,
                                  f.dest_path, f.canonical_sha
                           FROM files f WHERE f.sha256 IS NOT NULL AND f.state != 'missing'
                           ORDER BY f.root_index, f.relpath''').fetchall()
    result = {}
    for row in rows:
        result.setdefault(row[2], row)
    return result


def hamming(a, b):
    return bin(int(a, 16) ^ int(b, 16)).count('1')


def chunk_keys(value):
    number = int(value, 16)
    keys = []
    shift = 64
    for bits in CHUNK_BITS:
        shift -= bits
        keys.append((len(keys), (number >> shift) & ((1 << bits) - 1)))
    return keys


def find_visual_candidates(conn):
    unique = unique_hash_rows(conn)
    index = {}
    for digest, row in unique.items():
        if row[3] is None:
            continue
        for key in chunk_keys(row[3]):
            index.setdefault(key, []).append(digest)
    pairs = set()
    for digest, row in unique.items():
        if row[3] is None:
            continue
        possible = set()
        for key in chunk_keys(row[3]):
            possible.update(index.get(key, []))
        for other in possible:
            if other <= digest:
                continue
            distance = hamming(row[3], unique[other][3])
            if distance <= DHASH_DISTANCE_LIMIT:
                sha_a, sha_b = sorted((digest, other))
                conn.execute('''INSERT OR IGNORE INTO candidates
                    (sha_a, sha_b, distance, decision, active)
                    VALUES (?, ?, ?, 'pending', 1)''', (sha_a, sha_b, distance))
                conn.execute('''UPDATE candidates SET distance = ?, active = 1
                    WHERE sha_a = ? AND sha_b = ?''', (distance, sha_a, sha_b))
                pairs.add((sha_a, sha_b))
    conn.commit()
    return len(pairs)


def approved_components(conn, unique):
    parent = dict((digest, digest) for digest in unique)

    def find(value):
        while parent[value] != value:
            parent[value] = parent[parent[value]]
            value = parent[value]
        return value

    for sha_a, sha_b in conn.execute('''SELECT sha_a, sha_b FROM candidates
        WHERE active = 1 AND decision = 'approve' ''').fetchall():
        if sha_a in parent and sha_b in parent:
            root_a, root_b = find(sha_a), find(sha_b)
            if root_a != root_b:
                parent[root_b] = root_a
    groups = {}
    for digest in parent:
        groups.setdefault(find(digest), []).append(digest)
    return groups


def representative_order(row):
    return row[0], row[1]


def output_path(destination, root_index, relpath):
    return os.path.join(destination, 'photos', 'A' if root_index == 0 else 'B', relpath)


def safe_mkdir(path):
    if not os.path.isdir(path):
        os.makedirs(path)


def copy_verified(source, destination, expected_sha):
    safe_mkdir(os.path.dirname(destination))
    if os.path.exists(destination):
        if sha256_file(destination) == expected_sha:
            return
        raise DedupeError('Ya existe un archivo distinto en C: %s' % destination)
    temp = destination + '.dedupe-part'
    try:
        if os.path.exists(temp):
            os.unlink(temp)
        shutil.copy2(source, temp)
        if sha256_file(temp) != expected_sha:
            raise DedupeError('El checksum de la copia temporal no coincide: %s' % source)
        os.rename(temp, destination)
        if sha256_file(destination) != expected_sha:
            raise DedupeError('El checksum posterior a la copia no coincide: %s' % destination)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def run_copy(roots, mode, ffmpeg):
    source_a, source_b, destination = check_roots(*roots)
    safe_mkdir(destination)
    conn = connect_db(default_db(destination))
    try:
        set_roots(conn, [source_a, source_b, destination])
        records, issues = walk_sources([source_a, source_b, destination])
        add_inventory(conn, [source_a, source_b, destination], records, issues,
                      mode in ('visual-review', 'reviewed'), ffmpeg)
        error_count = conn.execute("SELECT COUNT(*) FROM files WHERE state = 'error'").fetchone()[0]
        if error_count:
            print('Aviso: %d foto(s) no pudieron leerse; se conservan los orígenes.' % error_count,
                  file=sys.stderr)
        if issues:
            print('Aviso: %d elemento(s) no reconocidos; bloquearán el borrado.' % len(issues),
                  file=sys.stderr)
            for root_index, relpath, detail in issues:
                print('  %s: %s' % (os.path.join((source_a, source_b)[root_index], relpath), detail),
                      file=sys.stderr)
        if mode == 'reviewed' and get_meta(conn, 'visual_scanned') != '1':
            raise DedupeError('Ejecuta primero el modo visual-review para generar candidatas.')
        if mode in ('visual-review', 'reviewed'):
            conn.execute('UPDATE candidates SET active = 0')
            conn.commit()
            candidate_count = find_visual_candidates(conn)
            set_meta(conn, 'visual_scanned', '1')
            conn.commit()
            if mode == 'visual-review':
                print('Candidatas visuales encontradas: %d' % candidate_count)
        if mode == 'reviewed':
            pending = conn.execute("SELECT COUNT(*) FROM candidates WHERE active = 1 AND decision = 'pending'").fetchone()[0]
            if pending:
                raise DedupeError('Hay %d candidata(s) pendientes; revísalas antes del modo reviewed.' % pending)
        unique = unique_hash_rows(conn)
        if mode == 'reviewed':
            components = approved_components(conn, unique)
        else:
            components = dict((digest, [digest]) for digest in unique)
        by_digest = unique
        processed = set()
        for digests in components.values():
            representative = min((by_digest[digest] for digest in digests), key=representative_order)
            rep_digest = representative[2]
            rep_source = os.path.join([source_a, source_b][representative[0]], representative[1])
            rep_destination = output_path(destination, representative[0], representative[1])
            if sha256_file(rep_source) != rep_digest:
                raise DedupeError('El origen cambió desde el inventario: %s' % rep_source)
            copy_verified(rep_source, rep_destination, rep_digest)
            if sha256_file(rep_destination) != rep_digest:
                raise DedupeError('No se pudo verificar la copia de %s' % rep_destination)
            for digest in digests:
                old_destinations = conn.execute('''SELECT root_index, relpath, dest_path FROM files
                    WHERE sha256 = ? AND state != 'missing' ''', (digest,)).fetchall()
                for old in old_destinations:
                    old_path = old[2]
                    if old_path and absolute(old_path) != absolute(rep_destination) and mode == 'reviewed':
                        if os.path.isfile(old_path) and sha256_file(old_path) == digest:
                            os.unlink(old_path)
                        elif os.path.exists(old_path):
                            raise DedupeError('No se quitó una copia secundaria modificada: %s' % old_path)
                    new_state = 'verified' if digest == rep_digest else 'reviewed_duplicate'
                    conn.execute('''UPDATE files SET state = ?, dest_path = ?, canonical_sha = ?,
                        error = NULL WHERE root_index = ? AND relpath = ?''',
                        (new_state, rep_destination, rep_digest, old[0], old[1]))
            conn.commit()
            processed.update(digests)
        report_path = os.path.join(destination, '.photo-dedupe', 'candidates.tsv')
        write_candidate_report(conn, [source_a, source_b], report_path)
        print('Fotos con SHA-256 único: %d' % len(unique))
        print('Copias únicas verificadas: %d' % len(processed))
        print('Base de control: %s' % default_db(destination))
        if mode in ('visual-review', 'reviewed'):
            print('Reporte visual: %s' % report_path)
        return 0 if not error_count else 2
    finally:
        conn.close()


def write_candidate_report(conn, roots, report_path):
    safe_mkdir(os.path.dirname(report_path))
    rows = conn.execute('''SELECT candidate_id, sha_a, sha_b, distance, decision
        FROM candidates WHERE active = 1 ORDER BY candidate_id''').fetchall()
    with open(report_path, 'w') as handle:
        handle.write('id\tdistancia_dhash\tdecision\tfoto_a\tfoto_b\n')
        for candidate_id, sha_a, sha_b, distance, decision in rows:
            a = conn.execute('''SELECT root_index, relpath FROM files WHERE sha256 = ?
                AND state != 'missing' ORDER BY root_index, relpath LIMIT 1''', (sha_a,)).fetchone()
            b = conn.execute('''SELECT root_index, relpath FROM files WHERE sha256 = ?
                AND state != 'missing' ORDER BY root_index, relpath LIMIT 1''', (sha_b,)).fetchone()
            path_a = os.path.join(roots[a[0]], a[1]) if a else sha_a
            path_b = os.path.join(roots[b[0]], b[1]) if b else sha_b
            handle.write('%s\t%s\t%s\t%s\t%s\n' %
                         (candidate_id, distance, decision, path_a, path_b))


def list_candidates(destination):
    destination = absolute(destination)
    db_path = default_db(destination)
    if not os.path.isfile(db_path):
        raise DedupeError('No existe la base SQLite: %s' % db_path)
    conn = connect_db(db_path)
    try:
        roots = [get_meta(conn, 'source_a'), get_meta(conn, 'source_b')]
        rows = conn.execute('''SELECT candidate_id, sha_a, sha_b, distance, decision
            FROM candidates WHERE active = 1 ORDER BY candidate_id''').fetchall()
        if not rows:
            print('No hay candidatas visuales activas.')
            return
        for candidate_id, sha_a, sha_b, distance, decision in rows:
            paths = []
            for digest in (sha_a, sha_b):
                row = conn.execute('''SELECT root_index, relpath FROM files WHERE sha256 = ?
                    AND state != 'missing' ORDER BY root_index, relpath LIMIT 1''', (digest,)).fetchone()
                paths.append(os.path.join(roots[row[0]], row[1]) if row else digest)
            print('%d\t%d bits\t%s\n  A: %s\n  B: %s' %
                  (candidate_id, distance, decision, paths[0], paths[1]))
    finally:
        conn.close()


def review_candidate(destination, candidate_id, decision):
    destination = absolute(destination)
    db_path = default_db(destination)
    if not os.path.isfile(db_path):
        raise DedupeError('No existe la base SQLite: %s' % db_path)
    conn = connect_db(db_path)
    try:
        cursor = conn.execute('''UPDATE candidates SET decision = ?
            WHERE candidate_id = ? AND active = 1''', (decision, candidate_id))
        conn.commit()
        if cursor.rowcount != 1:
            raise DedupeError('No existe una candidata activa con ID %s.' % candidate_id)
        print('Candidata %s marcada como %s.' % (candidate_id, decision))
    finally:
        conn.close()


def validate_sources_for_deletion(roots, ffmpeg):
    source_a, source_b, destination = check_roots(*roots)
    db_path = default_db(destination)
    if not os.path.isfile(db_path):
        raise DedupeError('No existe la base SQLite: %s' % db_path)
    conn = connect_db(db_path)
    try:
        ensure_db_roots(conn, [source_a, source_b, destination])
        records, issues = walk_sources([source_a, source_b, destination])
        if issues:
            details = ', '.join(os.path.join((source_a, source_b)[row[0]], row[1]) for row in issues[:5])
            raise DedupeError('Hay %d archivo(s) o elemento(s) sin procesar; no se borrará ningún origen. Ejemplos: %s' %
                              (len(issues), details))
        pending = conn.execute("SELECT COUNT(*) FROM candidates WHERE active = 1 AND decision = 'pending'").fetchone()[0]
        if pending:
            raise DedupeError('Hay %d candidata(s) visuales sin decisión.' % pending)
        current = set((row[0], row[1]) for row in records)
        pending_deletes = conn.execute('''SELECT root_index, relpath FROM files
            WHERE source_deleted = 0 AND state = 'delete_pending' ''').fetchall()
        for root_index, relpath in pending_deletes:
            source_path = os.path.join((source_a, source_b)[root_index], relpath)
            if not os.path.exists(source_path):
                conn.execute('''UPDATE files SET source_deleted = 1, state = 'source_deleted'
                    WHERE root_index = ? AND relpath = ?''', (root_index, relpath))
        conn.commit()
        tracked = set((row[0], row[1]) for row in conn.execute(
            "SELECT root_index, relpath FROM files WHERE source_deleted = 0 AND state NOT IN ('missing', 'delete_pending')"))
        tracked.update(set((root_index, relpath) for root_index, relpath in pending_deletes
                           if (root_index, relpath) in current))
        if current != tracked:
            raise DedupeError('El inventario actual no coincide con SQLite; vuelve a ejecutar el análisis.')
        for root_index, relpath, size, mtime, full in records:
            row = conn.execute('''SELECT sha256, state, dest_path, canonical_sha
                FROM files WHERE root_index = ? AND relpath = ?''', (root_index, relpath)).fetchone()
            if not row or not row[0] or row[1] not in ('verified', 'reviewed_duplicate', 'delete_pending'):
                raise DedupeError('La foto no tiene estado verificado: %s' % full)
            if sha256_file(full) != row[0]:
                raise DedupeError('El origen cambió después de verificarlo: %s' % full)
            if not row[2] or not os.path.isfile(row[2]):
                raise DedupeError('Falta la copia representativa en C para %s' % full)
            if sha256_file(row[2]) != row[3]:
                raise DedupeError('La copia en C no coincide con su hash de control: %s' % row[2])
        return conn, records
    except Exception:
        conn.close()
        raise


def delete_sources(roots, ffmpeg, confirmed):
    if not confirmed:
        raise DedupeError('El borrado requiere --confirm-delete.')
    conn, records = validate_sources_for_deletion(roots, ffmpeg)
    try:
        for root_index, relpath, size, mtime, full in records:
            conn.execute('''UPDATE files SET state = 'delete_pending'
                WHERE root_index = ? AND relpath = ?''', (root_index, relpath))
            conn.commit()
            os.unlink(full)
            conn.execute('''UPDATE files SET source_deleted = 1, state = 'source_deleted'
                WHERE root_index = ? AND relpath = ?''', (root_index, relpath))
            conn.commit()
        for root in roots[:2]:
            for current, directories, filenames in os.walk(root, topdown=False):
                for dirname in directories:
                    path = os.path.join(current, dirname)
                    if not os.path.islink(path):
                        try:
                            os.rmdir(path)
                        except OSError:
                            pass
            try:
                os.rmdir(root)
            except OSError:
                pass
        print('Orígenes borrados después de validar todas las fotos contra C.')
    finally:
        conn.close()


def make_parser():
    parser = argparse.ArgumentParser(description='Consolida fotos duplicadas con SQLite y verificación SHA-256.')
    parser.add_argument('--version', action='version', version=VERSION)
    subparsers = parser.add_subparsers(dest='command')
    run = subparsers.add_parser('run', help='inventaría, detecta y copia fotos únicas a C')
    run.add_argument('source_a')
    run.add_argument('source_b')
    run.add_argument('destination')
    run.add_argument('--mode', choices=('exact', 'visual-review', 'reviewed'), default='exact')
    run.add_argument('--ffmpeg', default='ffmpeg')
    candidates = subparsers.add_parser('candidates', help='lista coincidencias visuales por revisar')
    candidates.add_argument('destination')
    review = subparsers.add_parser('review', help='aprueba una coincidencia visual o la marca como distinta')
    review.add_argument('destination')
    review.add_argument('--id', type=int, required=True, dest='candidate_id')
    review.add_argument('--decision', choices=('approve', 'distinct'), required=True)
    delete = subparsers.add_parser('delete-sources', help='borra A y B solo después de la verificación completa')
    delete.add_argument('source_a')
    delete.add_argument('source_b')
    delete.add_argument('destination')
    delete.add_argument('--ffmpeg', default='ffmpeg')
    delete.add_argument('--confirm-delete', action='store_true',
                        help='confirmación explícita requerida para borrar los orígenes')
    return parser


def main(argv=None):
    args = make_parser().parse_args(argv)
    try:
        if args.command == 'run':
            return run_copy([args.source_a, args.source_b, args.destination], args.mode, args.ffmpeg)
        if args.command == 'candidates':
            list_candidates(args.destination)
            return 0
        if args.command == 'review':
            review_candidate(args.destination, args.candidate_id, args.decision)
            return 0
        if args.command == 'delete-sources':
            roots = check_roots(args.source_a, args.source_b, args.destination)
            delete_sources(roots, args.ffmpeg, args.confirm_delete)
            return 0
        make_parser().print_help()
        return 2
    except (DedupeError, IOError, OSError, sqlite3.Error) as exc:
        print('ERROR: %s' % exc, file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
