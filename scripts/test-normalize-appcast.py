import pathlib
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET


class AppcastTests(unittest.TestCase):
    def test_generated_links_are_repaired_without_changing_signed_metadata(self):
        fixture = '''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><sparkle:shortVersionString>0.1.8</sparkle:shortVersionString>
        <sparkle:version>9</sparkle:version><enclosure url="new.zip" length="123" sparkle:edSignature="signature-new"/>
        <sparkle:deltas><enclosure url="unpublished.delta"/></sparkle:deltas></item>
        <item><sparkle:shortVersionString>0.1.7</sparkle:shortVersionString>
        <sparkle:version>8</sparkle:version><enclosure url="https://github.com/darrellgardiner-clipflow-vibe/clearmic/releases/download/v0.1.8/ClearMic-0.1.7.zip" length="456" sparkle:edSignature="signature-old"/></item>
        </channel></rss>'''
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "appcast.xml"
            path.write_text(fixture)
            script = pathlib.Path(__file__).with_name("normalize-appcast.py")
            subprocess.run([sys.executable, script, path], check=True)
            items = ET.parse(path).findall("./channel/item")
            self.assertEqual([item.find("enclosure").get("url") for item in items], [
                "https://github.com/darrellgardiner-clipflow-vibe/clearmic/releases/download/v0.1.8/ClearMic-0.1.8.zip",
                "https://github.com/darrellgardiner-clipflow-vibe/clearmic/releases/download/v0.1.7/ClearMic-0.1.7.zip",
            ])
            sparkle = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
            self.assertEqual([item.find("enclosure").get(sparkle + "edSignature") for item in items], ["signature-new", "signature-old"])
            self.assertEqual([item.find("enclosure").get("length") for item in items], ["123", "456"])
            self.assertEqual([item.findtext(sparkle + "version") for item in items], ["9", "8"])
            self.assertEqual(ET.parse(path).findall(".//" + sparkle + "deltas"), [])
            once = path.read_bytes()
            subprocess.run([sys.executable, script, path], check=True)
            self.assertEqual(path.read_bytes(), once)


if __name__ == "__main__":
    unittest.main()
