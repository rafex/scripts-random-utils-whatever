import importlib.util
import os
import shutil
import tempfile
import unittest


SCRIPT = os.path.join(os.path.dirname(os.path.dirname(__file__)),
                      'scripts', 'backup', 'dedupe_photos_unix.py')
SPEC = importlib.util.spec_from_file_location('dedupe_photos_unix', SCRIPT)
DEDUPE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DEDUPE)


def write_ppm(path, comment=''):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as handle:
        handle.write(('P6\n# %s\n2 2\n255\n' % comment).encode('ascii'))
        handle.write(bytes([0, 0, 0, 255, 255, 255,
                            0, 0, 0, 255, 255, 255]))


class DedupePhotosTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ffmpeg = shutil.which('ffmpeg')
        if not cls.ffmpeg:
            raise unittest.SkipTest('FFmpeg no está disponible para las pruebas visuales.')

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix='dedupe-photos-test-')
        self.a = os.path.join(self.tmp, 'A')
        self.b = os.path.join(self.tmp, 'B')
        self.c = os.path.join(self.tmp, 'C')
        os.makedirs(self.a)
        os.makedirs(self.b)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_mode(self, mode):
        return DEDUPE.run_copy([self.a, self.b, self.c], mode, self.ffmpeg)

    def test_exact_duplicates_copy_once_and_resume(self):
        first = os.path.join(self.a, 'same.ppm')
        second = os.path.join(self.b, 'same-again.ppm')
        write_ppm(first)
        shutil.copy2(first, second)
        os.makedirs(os.path.join(self.c, 'photos', 'A'))
        with open(os.path.join(self.c, 'photos', 'A', 'same.ppm.dedupe-part'), 'wb') as handle:
            handle.write(b'interrupted partial')

        self.assertEqual(DEDUPE.run_copy([self.a, self.b, self.c], 'exact', self.ffmpeg), 0)
        self.assertEqual(DEDUPE.run_copy([self.a, self.b, self.c], 'exact', self.ffmpeg), 0)
        photos = [path for root, _, names in os.walk(os.path.join(self.c, 'photos'))
                  for path in [os.path.join(root, name) for name in names]]
        self.assertEqual(len(photos), 1)
        conn, _ = DEDUPE.validate_sources_for_deletion([self.a, self.b, self.c], self.ffmpeg)
        conn.close()

    def test_visual_candidate_requires_review_then_consolidates(self):
        write_ppm(os.path.join(self.a, 'photo-a.ppm'), 'first encoding')
        write_ppm(os.path.join(self.b, 'photo-b.ppm'), 'second encoding')
        self.assertEqual(self.run_mode('visual-review'), 0)
        conn = DEDUPE.connect_db(DEDUPE.default_db(self.c))
        candidate = conn.execute('SELECT candidate_id FROM candidates WHERE active = 1').fetchone()
        self.assertIsNotNone(candidate)
        conn.close()
        with self.assertRaises(DEDUPE.DedupeError):
            DEDUPE.validate_sources_for_deletion([self.a, self.b, self.c], self.ffmpeg)

        DEDUPE.review_candidate(self.c, candidate[0], 'approve')
        self.assertEqual(self.run_mode('reviewed'), 0)
        photos = [os.path.join(root, name) for root, _, names in os.walk(os.path.join(self.c, 'photos'))
                  for name in names]
        self.assertEqual(len(photos), 1)
        conn, records = DEDUPE.validate_sources_for_deletion([self.a, self.b, self.c], self.ffmpeg)
        conn.close()
        DEDUPE.delete_sources([self.a, self.b, self.c], self.ffmpeg, True)
        self.assertFalse(os.path.exists(self.a))
        self.assertFalse(os.path.exists(self.b))

    def test_unsupported_file_blocks_source_deletion(self):
        write_ppm(os.path.join(self.a, 'photo.ppm'))
        with open(os.path.join(self.b, 'notes.txt'), 'w') as handle:
            handle.write('keep this')
        self.assertEqual(self.run_mode('exact'), 0)
        with self.assertRaises(DEDUPE.DedupeError):
            DEDUPE.validate_sources_for_deletion([self.a, self.b, self.c], self.ffmpeg)
        self.assertTrue(os.path.exists(os.path.join(self.b, 'notes.txt')))

    def test_unreadable_image_and_corrupt_destination_block_delete(self):
        with open(os.path.join(self.a, 'bad.jpg'), 'wb') as handle:
            handle.write(b'not an image')
        self.assertEqual(self.run_mode('visual-review'), 2)
        with self.assertRaises(DEDUPE.DedupeError):
            DEDUPE.validate_sources_for_deletion([self.a, self.b, self.c], self.ffmpeg)

        shutil.rmtree(self.a)
        os.makedirs(self.a)
        write_ppm(os.path.join(self.a, 'good.ppm'))
        self.assertEqual(self.run_mode('exact'), 0)
        with open(os.path.join(self.c, 'photos', 'A', 'good.ppm'), 'ab') as handle:
            handle.write(b'corruption')
        with self.assertRaises(DEDUPE.DedupeError):
            DEDUPE.validate_sources_for_deletion([self.a, self.b, self.c], self.ffmpeg)


if __name__ == '__main__':
    unittest.main()
