"""Contract for the supplied mint polygon-head reference, not an antenna robot."""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET


class IconReferenceTests(unittest.TestCase):
    def test_reference_palette_and_silhouette(self):
        root = ET.parse(Path(__file__).resolve().parents[2] / 'assets/hermes-bot.svg').getroot()
        paths = root.findall('{http://www.w3.org/2000/svg}path')
        self.assertEqual([p.get('fill') for p in paths], ['#c9dbcb', '#0a130b', '#0a130b'])
        self.assertEqual(len(list(root)), 4)  # description + head + two slanted eyes
        self.assertFalse(root.findall('.//{http://www.w3.org/2000/svg}circle'))
        self.assertEqual(root.get('viewBox'), '10 1 22 25')
