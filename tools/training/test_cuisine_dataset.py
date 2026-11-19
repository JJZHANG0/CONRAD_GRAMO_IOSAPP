"""Data-integrity regression tests. Synthetic metadata only; no real training examples."""
import unittest
import subprocess,tempfile
from pathlib import Path
from unittest.mock import patch
from collect_cuisine_images import Client, category_files, merge_candidate, group_images
from export_reviewed_dataset import build_export

class DatasetSafetyTests(unittest.TestCase):
    def row(self,pid=1,**extra):
        return dict(page_id=pid,sha256=str(pid),suggested_group='g'+str(pid),review_status='pending',**extra)
    def review(self,pid=1,**extra):
        return dict(page_id=pid,decision='accept',dish_id='mapo',reviewer='test',plate_group='plate'+str(pid),split='train',**extra)
    @property
    def catalog(self):return [dict(dish_id='mapo',name_zh='麻婆豆腐',model_label_id=0),dict(dish_id='new',name_zh='新类别',model_label_id=None)]
    def test_download_failure_keeps_diagnostic(self):
        with tempfile.TemporaryDirectory() as d:
            client=Client(Path(d))
            error=subprocess.CalledProcessError(22,['curl'],stderr=b'HTTP 404')
            with patch('collect_cuisine_images.subprocess.run',side_effect=error):
                with self.assertRaisesRegex(RuntimeError,'curl exit 22.*HTTP 404'):
                    client.fetch('https://thumb.wikimedia.org/test.jpg',Path(d)/'image.jpg')
    def test_pagination_includes_later_pages(self):
        class Client:
            def query(self,**params):
                if 'cmcontinue' not in params:return {'query':{'categorymembers':[{'pageid':1}]},'continue':{'cmcontinue':'next','continue':'-||'}}
                return {'query':{'categorymembers':[{'pageid':2}]}}
        self.assertEqual([r['pageid'] for r in category_files(Client(),'Mapo doufu',2)],[1,2])
    def test_multidish_page_is_quarantined(self):
        records={}; page=dict(pageid=9,title='Multi-dish photo');info=dict(mime='image/jpeg',width=640,height=480,
            descriptionurl='https://commons.wikimedia.org/wiki/File:Example',url='https://upload.wikimedia.org/example.jpg',
            extmetadata={'LicenseShortName':{'value':'CC0'}})
        for dish in ['mapo','kungpao']:merge_candidate(records,page,info,dict(dish_id=dish,cuisines=['川菜']))
        self.assertEqual(records['9']['review_status'],'label_conflict');self.assertFalse(records['9']['training_eligible'])
    def test_unreviewed_images_never_export(self):
        self.assertEqual(build_export([self.row()],[],self.catalog),([],[]))
    def test_new_class_never_gets_a_fake_model_id(self):
        review=self.review();review['dish_id']='new'
        existing,new=build_export([self.row()],[review],self.catalog)
        self.assertEqual(existing,[]);self.assertIsNone(new[0]['model_label_id']);self.assertFalse(new[0]['training_eligible'])
    def test_author_or_plate_group_cannot_cross_splits(self):
        a,b=self.row(),self.row(2);b['suggested_group']=a['suggested_group']
        rb=self.review(2);rb['split']='test'
        with self.assertRaisesRegex(ValueError,'Cross-split'):build_export([a,b],[self.review(),rb],self.catalog)
    def test_prior_holdout_cannot_train(self):
        with self.assertRaisesRegex(ValueError,'held-out'):build_export([self.row(prior_experiment_split='test')],[self.review()],self.catalog)
    def test_visually_rejected_image_is_blocked(self):
        row=self.row();row['review_status']='rejected_visual'
        with self.assertRaises(ValueError):build_export([row],[self.review()],self.catalog)
    def test_exact_duplicate_conflicting_labels(self):
        rows=[dict(page_id=i,sha256='same',artist='A',dhash='0'*16,dish_ids=[label],review_status='pending') for i,label in [(1,'mapo'),(2,'kungpao')]]
        group_images(rows)
        self.assertEqual({r['review_status'] for r in rows},{'label_conflict'})
        self.assertEqual(len({r['suggested_group'] for r in rows}),1)

if __name__=='__main__':unittest.main()
