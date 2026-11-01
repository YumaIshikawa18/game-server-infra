import copy
import json
import os
import pathlib
import sys
import tempfile
import unittest
from unittest import mock

from scripts.cd import common, deploy, operations

ROOT = pathlib.Path(__file__).resolve().parents[2]


def plan_fixture():
  return {'format_version': '1.2', 'terraform_version': '1.17.1',
      'resource_changes': [{'address': 'module.server.aws_instance.minecraft',
                  'type': 'aws_instance', 'change': {'actions': ['update'],
                  'before': {'instance_type': 'old'},
                  'after': {'instance_type': 'new'}, 'after_unknown': {}}}]}


class Digest(unittest.TestCase):
  def test_identical_values_match(self):
    value = plan_fixture()
    self.assertEqual(deploy.digest(value), deploy.digest(copy.deepcopy(value)))

  def test_relevant_attribute_enumeration_order_does_not_change_digest(self):
    first = plan_fixture()
    first['relevant_attributes'] = [
      {'resource': 'data.aws_caller_identity.current', 'attribute': ['account_id']},
      {'resource': 'data.aws_ssm_parameter.ami', 'attribute': ['value']},
    ]
    second = copy.deepcopy(first)
    second['relevant_attributes'].reverse()
    self.assertEqual(deploy.digest(first), deploy.digest(second))

  def test_relevant_attribute_content_and_path_order_still_change_digest(self):
    first = plan_fixture()
    first['relevant_attributes'] = [{'resource': 'aws_instance.example', 'attribute': ['tags', 'Name']}]
    for changed in ([{'resource': 'aws_instance.other', 'attribute': ['tags', 'Name']}],
            [{'resource': 'aws_instance.example', 'attribute': ['Name', 'tags']}], []):
      with self.subTest(changed=changed):
        second = copy.deepcopy(first)
        second['relevant_attributes'] = changed
        self.assertNotEqual(deploy.digest(first), deploy.digest(second))

  def test_plan_and_apply_roles_produce_the_same_digest(self):
    # plan と apply は別のロールで plan を作るため、caller identity の arn / user_id が異なる。
    # これらは prior_state にだけ現れ、比較の対象にしない（Codex P1 の確認）。
    def with_caller(arn):
      value = plan_fixture()
      value['prior_state'] = {'values': {'root_module': {'resources': [{
        'address': 'data.aws_caller_identity.current', 'mode': 'data', 'type': 'aws_caller_identity',
        'values': {'account_id': '123456789012', 'arn': arn, 'id': '123456789012', 'user_id': arn[-8:]}}]}}}
      value['relevant_attributes'] = [{'resource': 'data.aws_caller_identity.current', 'attribute': ['account_id']}]
      return value
    plan_role = with_caller('arn:aws:sts::123456789012:assumed-role/example-ci-plan/run-1')
    apply_role = with_caller('arn:aws:sts::123456789012:assumed-role/example-ci-apply/run-2')
    self.assertEqual(deploy.digest(plan_role), deploy.digest(apply_role))

  def test_value_change_with_same_action_is_detected(self):
    before = plan_fixture()
    after = copy.deepcopy(before)
    after['resource_changes'][0]['change']['after']['instance_type'] = 'different'
    self.assertNotEqual(deploy.digest(before), deploy.digest(after))

  def test_unknown_and_output_changes_are_detected(self):
    original = plan_fixture()
    after = copy.deepcopy(original)
    after['resource_changes'][0]['change']['after_unknown'] = {'id': True}
    self.assertNotEqual(deploy.digest(original), deploy.digest(after))
    after = copy.deepcopy(original)
    after['output_changes'] = {'result': {'after': 'changed'}}
    self.assertNotEqual(deploy.digest(original), deploy.digest(after))

  def test_timestamp_does_not_change_digest(self):
    before = plan_fixture()
    after = copy.deepcopy(before)
    after['timestamp'] = 'different-time'
    self.assertEqual(deploy.digest(before), deploy.digest(after))

  def test_key_order_does_not_change_digest(self):
    before = plan_fixture()
    self.assertEqual(deploy.digest(before), deploy.digest(dict(reversed(list(before.items())))))

  def test_replacement_under_module_detected(self):
    value = plan_fixture()
    value['resource_changes'][0]['change']['actions'] = ['delete', 'create']
    identity = 'i-' + 'a' * 17
    value['resource_changes'][0]['change']['before']['id'] = identity
    self.assertEqual(deploy.replacement_ids(value), [identity])

  def test_replacement_without_identity_rejected(self):
    value = plan_fixture()
    value['resource_changes'][0]['change']['actions'] = ['delete', 'create']
    with self.assertRaises(ValueError):
      deploy.replacement_ids(value)


class Locks(unittest.TestCase):
  def setUp(self):
    self.environment = mock.patch.dict(os.environ, {
      'MC_LOCK_BUCKET': 'example', 'MC_LOCK_KEY': 'control/operation.lock',
      'GITHUB_RUN_ID': 'test-run', 'GITHUB_RUN_ATTEMPT': '1'})
    self.environment.start()
    self.directory = tempfile.TemporaryDirectory(dir=pathlib.Path.cwd())
    self.root = mock.patch.object(common, 'ROOT', pathlib.Path(self.directory.name))
    self.root.start()

  def tearDown(self):
    self.root.stop()
    self.directory.cleanup()
    self.environment.stop()

  def test_acquire_and_conditional_release(self):
    with mock.patch.object(common, 'aws', return_value={'ETag': 'etag'}) as aws:
      with common.Lock():
        pass
    self.assertIn('--if-none-match', aws.call_args_list[0].args)
    self.assertIn('--if-match', aws.call_args_list[1].args)
    self.assertEqual(aws.call_args_list[1].args[-1], 'etag')

  def test_conflict_retried_then_acquired(self):
    with mock.patch.object(common, 'aws', side_effect=[common.AwsError('PreconditionFailed'),
                {'ETag': 'etag'}, {}]) as aws, mock.patch.object(common.time, 'sleep'):
      with common.Lock():
        pass
    self.assertEqual(aws.call_count, 3)

  def test_lock_timeout_does_not_delete_another_lock(self):
    with mock.patch.object(common, 'aws', side_effect=common.AwsError('PreconditionFailed')) as aws:
      with self.assertRaises(TimeoutError):
        with common.Lock(timeout=0):
          self.fail('lock must not be acquired')
    self.assertEqual(aws.call_count, 1)

  def test_access_denied_not_retried(self):
    with mock.patch.object(common, 'aws', side_effect=common.AwsError('AccessDenied')) as aws:
      with self.assertRaises(common.AwsError):
        with common.Lock():
          pass
    self.assertEqual(aws.call_count, 1)

  def test_keep_lock_after_uncertain_mutation(self):
    with (mock.patch.object(common, 'aws', return_value={'ETag': 'etag'}) as aws,
        mock.patch.object(common, 'summary')):
      with common.Lock() as lock:
        lock.keep = True
    self.assertEqual(aws.call_count, 1)

  def test_state_lock_key_rejected(self):
    with mock.patch.dict(os.environ, {'MC_LOCK_KEY': 'prod.tfstate.tflock'}):
      with self.assertRaises(ValueError):
        common.Lock().__enter__()


class Operations(unittest.TestCase):
  def test_current_instance_discovered_without_stale_secret(self):
    identity = 'i-' + 'a' * 17
    with (mock.patch.dict(os.environ, {'MC_INSTANCE_ID': ''}),
        mock.patch.object(common, 'aws', return_value={
          'Reservations': [{'Instances': [{'InstanceId': identity}]}]})):
      self.assertEqual(common.instance_id(), identity)

  def test_ambiguous_instance_discovery_rejected(self):
    with (mock.patch.dict(os.environ, {'MC_INSTANCE_ID': ''}),
        mock.patch.object(common, 'aws', return_value={'Reservations': []})):
      with self.assertRaises(ValueError):
        common.instance_id()

  def test_start_happy_path(self):
    lock = mock.Mock()
    with (mock.patch.object(common, 'instance', return_value={'State': {'Name': 'stopped'}}),
        mock.patch.object(common, 'instance_id', return_value='example'),
        mock.patch.object(common, 'aws') as aws,
        mock.patch.object(common, 'wait_state'), mock.patch.object(common, 'wait_ssm'),
        mock.patch.object(common, 'health') as health, mock.patch.object(common, 'summary')):
      operations.start(lock)
    self.assertEqual(aws.call_args.args[:2], ('ec2', 'start-instances'))
    health.assert_called_once()
    self.assertFalse(lock.keep)

  def test_restore_happy_path_leaves_stopped(self):
    lock = mock.Mock()
    with (mock.patch.dict(os.environ, {'RESTORE_KEY': 'stop/example.tar.zst'}),
        mock.patch.object(common, 'instance', return_value={'State': {'Name': 'stopped'}}),
        mock.patch.object(common, 'instance_id', return_value='example'),
        mock.patch.object(common, 'aws') as aws, mock.patch.object(common, 'wait_state'),
        mock.patch.object(common, 'wait_ssm'), mock.patch.object(common, 'send', return_value='command') as send,
        mock.patch.object(common, 'wait_command') as wait, mock.patch.object(common, 'summary')):
      operations.restore(lock)
    send.assert_called_once_with('mc-restore-apply', {'key': ['stop/example.tar.zst']})
    # 復元の実行上限（SSM 文書の 1800 秒）より長く待ってから停止する。
    self.assertGreater(wait.call_args.kwargs['timeout'], 1800)
    self.assertEqual(aws.call_args_list[-2].args[:2], ('ec2', 'stop-instances'))
    self.assertEqual(aws.call_args_list[-1].args[:2], ('ec2', 'delete-tags'))
    self.assertFalse(lock.keep)

  def test_stop_falls_back_when_ssm_unavailable(self):
    with (mock.patch.object(common, 'instance', return_value={'State': {'Name': 'running'}}),
        mock.patch.object(common, 'instance_id', return_value='example'),
        mock.patch.object(common, 'wait_ssm', side_effect=TimeoutError),
        mock.patch.object(common, 'aws') as aws, mock.patch.object(common, 'wait_state'),
        mock.patch.object(common, 'notify') as notify):
      common.stop('manual')
    self.assertEqual(aws.call_args.args[:2], ('ec2', 'stop-instances'))
    notify.assert_called_once_with('backup-unavailable', 'warn')

  def test_backup_key(self):
    self.assertEqual(operations.backup_key('stop/example.tar.zst'), 'stop/example.tar.zst')

  def test_bad_backup_keys(self):
    for key in ('stop/../world.tar.zst', 'deploy/example.tar.zst',
          'stop/$(command).tar.zst', 'hourly//world.tar.zst', 'stop/example.zip'):
      with self.subTest(key=key), self.assertRaises(ValueError):
        operations.backup_key(key)

  def test_restore_requires_stopped_instance(self):
    with (mock.patch.dict(os.environ, {'RESTORE_KEY': 'stop/example.tar.zst'}),
        mock.patch.object(common, 'instance', return_value={'State': {'Name': 'running'}}),
        mock.patch.object(common, 'aws') as aws):
      with self.assertRaises(ValueError):
        operations.restore(mock.Mock())
    aws.assert_not_called()

  def test_restore_failure_stops_before_clearing_tag(self):
    lock = mock.Mock()
    events = []
    def aws(*args):
      events.append(args[1])
      return {}
    with (mock.patch.dict(os.environ, {'RESTORE_KEY': 'stop/example.tar.zst'}),
        mock.patch.object(common, 'instance', return_value={'State': {'Name': 'stopped'}}),
        mock.patch.object(common, 'instance_id', return_value='example'),
        mock.patch.object(common, 'aws', side_effect=aws),
        mock.patch.object(common, 'wait_state', side_effect=lambda *a: events.append('wait-stopped')),
        mock.patch.object(common, 'wait_ssm', side_effect=TimeoutError)):
      with self.assertRaises(TimeoutError):
        operations.restore(lock)
    self.assertLess(events.index('stop-instances'), events.index('delete-tags'))
    self.assertEqual(events[-2:], ['wait-stopped', 'delete-tags'])
    self.assertFalse(lock.keep)

  def test_failed_cleanup_keeps_lock(self):
    lock = mock.Mock()
    with (mock.patch.dict(os.environ, {'RESTORE_KEY': 'stop/example.tar.zst'}),
        mock.patch.object(common, 'instance', return_value={'State': {'Name': 'stopped'}}),
        mock.patch.object(common, 'instance_id', return_value='example'),
        mock.patch.object(common, 'aws', side_effect=common.AwsError('AccessDenied'))):
      with self.assertRaises(common.AwsError):
        operations.restore(lock)
    self.assertTrue(lock.keep)

  def test_start_in_restore_mode_rejected(self):
    with (mock.patch.object(common, 'instance', return_value={
      'State': {'Name': 'stopped'}, 'Tags': [{'Key': 'mc:mode', 'Value': 'restore'}]}),
        mock.patch.object(common, 'aws') as aws):
      with self.assertRaises(ValueError):
        operations.start(mock.Mock())
    aws.assert_not_called()

  def test_start_failure_stops_host(self):
    lock = mock.Mock()
    with (mock.patch.object(common, 'instance', return_value={'State': {'Name': 'running'}}),
        mock.patch.object(common, 'wait_ssm', side_effect=TimeoutError),
        mock.patch.object(common, 'stop') as stop):
      with self.assertRaises(TimeoutError):
        operations.start(lock)
    stop.assert_called_once_with('start-failed')
    self.assertFalse(lock.keep)


class Deployment(unittest.TestCase):
  def test_failure_diagnostics_keep_primary_and_cleanup_steps_without_raw_values(self):
    raw = 'private-bucket account=123456789012 credential=do-not-print'
    with (mock.patch.object(sys, 'argv', ['deploy', 'apply']),
        mock.patch.object(deploy, 'apply') as apply, mock.patch('builtins.print') as output):
      def fail():
        try:
          with deploy.step('approval-comparison'):
            raise ValueError(raw)
        except ValueError:
          with deploy.step('operational-lock'):
            raise common.AwsError('AccessDenied')
      apply.side_effect = fail
      self.assertEqual(deploy.main(), 1)
    messages = '\n'.join(str(call.args[0]) for call in output.call_args_list)
    self.assertNotIn(raw, messages)
    self.assertIn('AccessDenied', messages)
    self.assertIn('approval-comparison', messages)
    self.assertIn('operational-lock', messages)

  def test_unknown_diagnostic_attributes_are_not_printed(self):
    error = common.AwsError('private-value/not-an-error-code')
    error._deployment_step = 'private-value'
    self.assertEqual(deploy.diagnostics(error), [
      {'step': 'unknown', 'kind': 'aws', 'aws_code': 'Unknown'}])

  def test_changed_plan_never_applied(self):
    with (mock.patch.dict(os.environ, {'EXPECTED_PLAN_DIGEST': 'a' * 64}),
        mock.patch.object(common, 'require_master'),
        mock.patch.object(common, 'Lock'), mock.patch.object(common, 'private_work'),
        mock.patch.object(deploy, 'make_plan', return_value=('unused', plan_fixture())),
        mock.patch.object(deploy, 'replacement_stop') as stop,
        mock.patch.object(deploy.ci, 'terraform') as terraform):
      with self.assertRaises(ValueError):
        deploy.apply()
    stop.assert_not_called()
    terraform.assert_not_called()

  def test_apply_failure_keeps_lock(self):
    value = plan_fixture()
    lock = mock.Mock()
    context = mock.MagicMock()
    context.__enter__.return_value = lock
    with (mock.patch.dict(os.environ, {'EXPECTED_PLAN_DIGEST': deploy.digest(value)}),
        mock.patch.object(common, 'require_master'),
        mock.patch.object(common, 'Lock', return_value=context),
        mock.patch.object(common, 'private_work'),
        mock.patch.object(deploy, 'make_plan', return_value=('unused', value)),
        mock.patch.object(deploy, 'replacement_stop'),
        mock.patch.object(deploy.ci, 'terraform', side_effect=RuntimeError),
        mock.patch.object(deploy, 'smoke') as smoke):
      with self.assertRaises(RuntimeError):
        deploy.apply()
    self.assertTrue(lock.keep)
    smoke.assert_not_called()

  def test_replacement_never_forces_stop_on_backup_failure(self):
    value = plan_fixture()
    identity = 'i-' + 'a' * 17
    value['resource_changes'][0]['change'].update(actions=['delete', 'create'], before={'id': identity})
    with (mock.patch.object(common, 'instance_id', return_value=identity),
        mock.patch.object(common, 'instance', return_value={'State': {'Name': 'running'}}),
        mock.patch.object(common, 'wait_ssm', side_effect=TimeoutError),
        mock.patch.object(common, 'aws') as aws):
      with self.assertRaises(TimeoutError):
        deploy.replacement_stop(value)
    aws.assert_not_called()

  def test_replacement_waits_for_the_full_host_stop(self):
    # mc-stop（900 秒）が終わる前にタイムアウトして apply を中止しない。
    value = plan_fixture()
    identity = 'i-' + 'a' * 17
    value['resource_changes'][0]['change'].update(actions=['delete', 'create'], before={'id': identity})
    with (mock.patch.object(common, 'instance_id', return_value=identity),
        mock.patch.object(common, 'instance', return_value={'State': {'Name': 'running'}}),
        mock.patch.object(common, 'wait_ssm'), mock.patch.object(common, 'send', return_value='command'),
        mock.patch.object(common, 'wait_command') as wait, mock.patch.object(common, 'wait_state')):
      deploy.replacement_stop(value)
    self.assertGreater(wait.call_args.kwargs['timeout'], 900)

  def test_wrong_revision_rejected(self):
    with (mock.patch.dict(os.environ, {'GITHUB_REF': 'refs/heads/master', 'GITHUB_SHA': 'a' * 40}),
        mock.patch.object(common.subprocess, 'run', return_value=mock.Mock(stdout=('b' * 40 + '\tmaster').encode()))):
      with self.assertRaises(ValueError):
        common.require_master()

  def test_notification_contains_no_instance_or_topic(self):
    with (mock.patch.dict(os.environ, {'MC_EVENTS_TOPIC_ARN': 'example-topic'}),
        mock.patch.object(common, 'aws') as aws):
      common.notify('deployment-failed')
    args = aws.call_args.args
    message = args[args.index('--message') + 1]
    self.assertNotIn('example-topic', message)
    self.assertNotIn('instance', message)
    self.assertEqual(json.loads(message)['event'], 'deployment-failed')

  def test_manual_stop_waits_longer_than_host_stop_window(self):
    # mc-stop（900 秒）と停止予約の後まで待ってから、バックアップなしの停止に切り替える。
    with (mock.patch.object(common, 'instance', return_value={'State': {'Name': 'running'}}),
        mock.patch.object(common, 'wait_ssm'), mock.patch.object(common, 'send'),
        mock.patch.object(common, 'wait_state') as wait):
      common.stop('manual')
    self.assertGreater(wait.call_args.kwargs['timeout'], 900 + 15)

  def test_notification_is_recognized_as_workflow_error(self):
    # notifier が独自形式として扱い、error の severity を保つには source が必要。
    sys.path.insert(0, str(ROOT / 'lambda/notifier'))
    import notifier
    with (mock.patch.dict(os.environ, {'MC_EVENTS_TOPIC_ARN': 'example-topic'}),
        mock.patch.object(common, 'aws') as aws):
      common.notify('start-failed')
    args = aws.call_args.args
    message = args[args.index('--message') + 1]
    self.assertEqual(json.loads(message)['source'], 'workflow')
    self.assertEqual(notifier.classify(message)[0], 'error')


if __name__ == '__main__':
  unittest.main()
