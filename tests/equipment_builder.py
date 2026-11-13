"""Reference classification regressions; no external archive needed."""
import pathlib
import sys
import unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'tools'))
from build_equipment_catalog import family, base_name, normal

class EquipmentBuilderTests(unittest.TestCase):
    def test_spikes_are_not_pikes(self):
        self.assertEqual(family('Spiked Mace','weapons'),'hammer')
        self.assertEqual(family('Pike','weapons'),'spear')
        self.assertEqual(family('Shield Crossbow','weapons'),'crossbow')
    def test_internal_variant_labels(self):
        known={normal('Broken Straight Sword'),normal('Dagger')}
        self.assertEqual(base_name('Broken Heavy Straight Sword',known),('Broken Straight Sword','Anchor'))
        self.assertEqual(base_name('Sharp Dagger',known),('Dagger','Edge'))
    def test_real_base_names_are_preserved(self):
        known={normal('Heavy Crossbow'),normal('Dark Sword')}
        self.assertEqual(base_name('Heavy Crossbow',known),('Heavy Crossbow',''))
        self.assertEqual(base_name('Dark Sword',known),('Dark Sword',''))

if __name__=='__main__':unittest.main()
