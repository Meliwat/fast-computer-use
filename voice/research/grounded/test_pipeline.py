import unittest
from pipeline import GroundedPipeline,mentioned_candidates,qualified_request

class Intent:
    def __init__(self,operation,confidence=1): self.operation=operation; self.confidence=confidence
    def predict(self,text):return {'operation':self.operation,'confidence':self.confidence}
class Ranker:
    def predict(self,text,observation):
        c=observation['candidates'][0]
        return {'command':{'op':'click','targetId':c['id'],'documentId':observation['documentId'],'observationId':observation['observationId']},'scores':[{'id':c['id'],'score':.999}], 'margin':.99}

class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.obs={'version':1,'documentId':'d','observationId':'o','truncated':False,'candidates':[
            {'id':'input','role':'input','labels':['search'],'enabled':True,'editable':True,'clickable':True},
            {'id':'download','role':'button','labels':['downloads'],'enabled':True,'editable':False,'clickable':True}]}
    def predict(self,op,text='open Downloads',confidence=1):
        return GroundedPipeline(Intent(op,confidence),Ranker()).predict(text,self.obs)
    def test_unique_observed_name_does_not_need_semantic_ranking(self):
        self.obs['candidates'][1]['labels']=['Cobalt workspace']
        self.assertEqual(self.predict('activate','open Cobalt workspace')['command']['targetId'],'download')
        self.assertEqual(self.predict('activate','open Cobalt workspace')['source'],'observed_label')
    def test_multiple_explicit_names_are_ambiguous(self):
        self.obs['candidates'].append({'id':'help','role':'button','labels':['help'],'enabled':True,'editable':False,'clickable':True})
        self.assertIsNone(self.predict('activate','open Downloads and Help')['command'])
    def test_disabled_explicit_name_does_not_fall_through_to_other_target(self):
        self.obs['candidates'][1]['enabled']=False
        self.obs['candidates'].append({'id':'help','role':'button','labels':['help'],'enabled':True,'editable':False,'clickable':True})
        self.assertIsNone(self.predict('activate','open Downloads')['command'])
    def test_delete_cannot_be_converted_into_target_click(self):
        self.assertIsNone(self.predict('abstain','delete Downloads')['command'])
    def test_uncertain_operation_never_calls_ranker(self):
        self.assertIsNone(self.predict('activate',confidence=.7)['command'])
    def test_operation_restricts_target_capability(self):
        self.assertEqual(self.predict('activate')['command']['targetId'],'download')
        self.assertEqual(self.predict('focus','focus Search')['command']['targetId'],'input')
    def test_requires_production_observation_capabilities(self):
        del self.obs['candidates'][1]['clickable']
        self.assertIsNone(self.predict('activate')['command'])
    def test_disabled_targets_are_not_candidates(self):
        self.obs['candidates'][1]['enabled']=False
        self.assertIsNone(self.predict('activate')['command'])
    def test_unknown_operation_cannot_turn_into_click(self):
        self.assertIsNone(self.predict('delete')['command'])
    def test_truncated_scene_and_duplicate_ids_abstain(self):
        self.obs['truncated']=True
        self.assertIsNone(self.predict('activate')['command'])
        self.obs['truncated']=False
        self.obs['candidates'].append(self.obs['candidates'][1].copy())
        self.assertIsNone(self.predict('activate')['command'])
    def test_cross_role_homonyms_need_explicit_role(self):
        self.obs['candidates'][1]['labels']=['search']
        self.assertIsNone(self.predict('activate','click Search')['command'])
        self.assertIsNotNone(self.predict('activate','click Search button')['command'])
    def test_complete_label_wins_over_its_prefix(self):
        self.obs['candidates'][1]['labels']=['Save']
        self.obs['candidates'].append(dict(self.obs['candidates'][1],id='save-as',labels=['Save as']))
        self.assertEqual(self.predict('activate','bring up Save as')['command']['targetId'],'save-as')
        self.assertEqual(self.predict('activate','press Save')['command']['targetId'],'download')
        self.assertIsNone(self.predict('activate','show Save and Save as')['command'])
    def test_disabled_long_label_does_not_select_shorter_enabled_label(self):
        self.obs['candidates'][1]['labels']=['Account']
        self.obs['candidates'].append(dict(self.obs['candidates'][1],id='settings',labels=['Account settings'],enabled=False))
        self.assertIsNone(self.predict('activate','show Account settings')['command'])
    def test_duplicate_complete_names_are_still_ambiguous(self):
        self.obs['candidates'][1]['labels']=['Save as']
        self.obs['candidates'].append(dict(self.obs['candidates'][1],id='duplicate'))
        self.assertIsNone(self.predict('activate','show Save as')['command'])
    def test_command_verb_is_not_a_control_mention(self):
        controls=[dict(id='open',labels=['Open']),dict(id='click',labels=['Click'])]
        for text in ['Open Export PDF','Please open Export PDF','Please could you open Export PDF',
                     'Now, please open Export PDF',"I'd like to open Export PDF",'Click Export PDF']:
            with self.subTest(text=text):self.assertEqual(mentioned_candidates(text,controls),[])
        for text in ['Open Open','Click Open','Bring up Open','Please open Open','I want Open']:
            with self.subTest(text=text):self.assertEqual([c['id'] for c in mentioned_candidates(text,controls)],['open'])
    def test_operator_collision_reaches_ranker_instead_of_binding(self):
        class Rejector:
            def predict(self,text,observation):return dict(command=None,reason='uncertain',scores=[])
        self.obs['candidates'][1]['labels']=['Open']
        result=GroundedPipeline(Intent('activate'),Rejector()).predict('Open Export PDF',self.obs)
        self.assertIsNone(result['command']);self.assertEqual(result['source'],'semantic_ranker')
    def test_explicit_role_selects_between_equal_names(self):
        self.obs['candidates']=[dict(id=role,role=role,labels=['notifications'],enabled=True,editable=False,clickable=True) for role in ['button','link','switch','checkbox']]
        for role in ['button','link','switch','checkbox']:
            self.assertEqual(self.predict('activate','click Notifications '+role)['command']['targetId'],role)
        self.assertIsNone(self.predict('activate','click Notifications')['command'])
    def test_role_mismatch_does_not_fall_through_to_another_label(self):
        self.obs['candidates'].append(dict(self.obs['candidates'][1],id='link',role='link',labels=['help']))
        self.assertIsNone(self.predict('activate','click Downloads link')['command'])
    def test_disabled_role_does_not_use_enabled_homonym(self):
        c=self.obs['candidates'][1];c.update(role='link',enabled=False)
        self.obs['candidates'].append(dict(c,id='other',role='button',enabled=True))
        self.assertIsNone(self.predict('activate','click Downloads link')['command'])
        self.assertEqual(self.predict('activate','click Downloads button')['command']['targetId'],'other')
    def test_role_word_is_not_a_separate_control_mention(self):
        self.obs['candidates']=[dict(id='target',role='link',labels=['notifications'],enabled=True,editable=False,clickable=True),dict(id='word',role='link',labels=['link'],enabled=True,editable=False,clickable=True)]
        self.assertEqual(self.predict('activate','click Notifications link')['command']['targetId'],'target')
        self.obs['candidates'][0]['role']='checkbox'
        self.assertIsNone(self.predict('activate','click Notifications link')['command'])
    def test_literal_label_with_role_noun_stays_literal(self):
        for label in ['Help link','Radio settings','Switch','Radio button']:
            self.obs['candidates']=[dict(id='literal',role='button',labels=[label],enabled=True,editable=False,clickable=True)]
            self.assertEqual(self.predict('activate','click '+label)['command']['targetId'],'literal')
    def test_role_normalization_preserves_negation_and_operator(self):
        for text in ["Don't click Notifications checkbox",'Delete Notifications switch','Uncheck Notifications checkbox']:
            _,normalized,_=qualified_request(text)
            self.assertEqual(normalized,text.rsplit(' ',1)[0]+' button')
        self.assertIsNone(self.predict('abstain',"Don't click Downloads button")['command'])
    def test_search_is_the_label_before_a_field_qualifier(self):
        self.assertEqual(self.predict('focus','Focus the Search field')['command']['targetId'],'input')
        self.assertEqual(self.predict('focus','Focus the Search box')['command']['targetId'],'input')

if __name__=='__main__':unittest.main()
