import unittest
from ranker import bind_selection

class BindingTests(unittest.TestCase):
    def setUp(self):
        self.observation = {'documentId':'doc-a','observationId':'obs-a','candidates':[
            {'id':'one','role':'link','label':'Inbox','enabled':True},
            {'id':'two','role':'textbox','label':'Search','enabled':True}]}
    def test_binds_only_observed_identity(self):
        self.assertEqual(bind_selection(self.observation,'one',.99,.3),
            {'op':'click','targetId':'one','documentId':'doc-a','observationId':'obs-a'})
    def test_focus_is_click_on_observed_field_without_generated_text(self):
        self.assertEqual(bind_selection(self.observation,'two',.99,.3)['targetId'],'two')
    def test_reject_unknown_disabled_duplicate_or_unbound(self):
        self.assertIsNone(bind_selection(self.observation,'invented',1,1))
        self.observation['candidates'][0]['enabled']=False
        self.assertIsNone(bind_selection(self.observation,'one',1,1))
        self.observation['candidates'].append(self.observation['candidates'][1].copy())
        self.assertIsNone(bind_selection(self.observation,'two',1,1))
        self.observation.pop('documentId')
        self.assertIsNone(bind_selection(self.observation,'two',1,1))
    def test_ambiguous_or_low_confidence_abstains(self):
        self.assertIsNone(bind_selection(self.observation,'one',.8,.5))
        self.assertIsNone(bind_selection(self.observation,'one',.99,.01))
        self.assertIsNone(bind_selection(self.observation,'one',float('nan'),.5))
    def test_reject_unsupported_role(self):
        self.observation['candidates'][0]['role']='select'
        self.assertIsNone(bind_selection(self.observation,'one',1,1))

if __name__=='__main__': unittest.main()
