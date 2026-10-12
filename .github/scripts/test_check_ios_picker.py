import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("check_ios_picker", Path(__file__).with_name("check_ios_picker.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PickerBuildTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.lock = self.root / "Podfile.lock"
        self.lock.write_text("PODS:\n  - file_picker (0.0.1):\n    - Flutter\n")
        support = self.root / "Pods/Target Support Files/file_picker"
        support.mkdir(parents=True)
        self.configs = []
        for mode in ("debug", "profile", "release"):
            config = support / f"file_picker.{mode}.xcconfig"
            config.write_text("GCC_PREPROCESSOR_DEFINITIONS = $(inherited) PICKER_DOCUMENT=1\n")
            self.configs.append(config)

    def test_document_only(self):
        module.check_picker(self.root)

    def test_media_dependencies_rejected(self):
        for name in ("DKCamera", "DKImagePickerController"):
            with self.subTest(name=name):
                self.lock.write_text(f"PODS:\n  - file_picker (0.0.1)\n  - {name} (1.0)\n")
                with self.assertRaisesRegex(ValueError, "dependencies"):
                    module.check_picker(self.root)

    def test_swift_package_bypass_rejected(self):
        self.lock.write_text("PODS:\n  - Flutter (1.0.0)\n")
        with self.assertRaisesRegex(ValueError, "CocoaPods"):
            module.check_picker(self.root)

    def test_missing_generated_configs_rejected(self):
        for config in self.configs:
            config.unlink()
        with self.assertRaisesRegex(ValueError, "Missing generated"):
            module.check_picker(self.root)

    def test_media_and_audio_defines_rejected_even_when_zero(self):
        for name in ("MEDIA", "AUDIO"):
            with self.subTest(name=name):
                self.configs[-1].write_text(f"PICKER_DOCUMENT=1 PICKER_{name}=0\n")
                with self.assertRaisesRegex(ValueError, "compiled in"):
                    module.check_picker(self.root)

    def test_disabled_document_picker_rejected(self):
        self.configs[-1].write_text("PICKER_DOCUMENT=0\n")
        with self.assertRaisesRegex(ValueError, "not enabled"):
            module.check_picker(self.root)

    def test_missing_lock_rejected(self):
        self.lock.unlink()
        with self.assertRaises(OSError):
            module.check_picker(self.root)


if __name__ == "__main__":
    unittest.main()
