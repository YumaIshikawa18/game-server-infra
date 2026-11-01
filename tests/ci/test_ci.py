import importlib.util
import pathlib
import unittest
import urllib.error

ROOT = pathlib.Path(__file__).resolve().parents[2]


def load(name):
  spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts/ci' / f'{name}.py')
  module = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(module)
  return module


check = load('check')
plan = load('plan')
client_guide = load('client_guide')


class Identifiers(unittest.TestCase):
  def test_examples_and_allowed_values(self):
    for value in ('123456789012', '192.0.2.1', '198.51.100.2', '203.0.113.3',
            '10.20.0.0/24', '172.16.0.1', '192.168.0.1', '0.0.0.0/0',
            'noreply@github.com', 'user@example.com', 'arn:aws:iam::aws:policy/Test'):
      with self.subTest(value=value):
        self.assertFalse(check.findings(value))

  def test_disallowed_patterns(self):
    # 検査対象の値そのものを追跡ファイルに残さない。
    values = ['987654' + '321098', '8.' + '8.8.8', 'person' + '@' + 'private.invalid',
          'https://discord.com/' + 'api/webhooks/token']
    for value in values:
      with self.subTest(kind=values.index(value)):
        self.assertTrue(check.findings(value))

  def test_account_id_in_arn(self):
    self.assertIn('account-id', check.findings('arn:aws:iam::' + '987654' + '321098' + ':role/test'))

  def test_not_a_12_digit_id_substring(self):
    self.assertNotIn('account-id', check.findings('9' * 13))

  def test_hash_and_ssh_url_are_not_identifiers(self):
    self.assertFalse(check.findings('a' + '9' * 12 + 'f'))
    self.assertFalse(check.findings('git@github.com:owner/repo.git'))
    self.assertFalse(check.findings('127.0.0.1'))


class Summary(unittest.TestCase):
  def change(self, address='aws_instance.minecraft', actions=None, **extra):
    return {'format_version': '1.2', 'resource_changes': [{'address': address, 'change': {
      'actions': actions or ['create'], 'after': {'secret': 'never-publish-this'}}, **extra}]}

  def test_only_addresses_and_counts(self):
    summary = plan.summarize(self.change())
    self.assertIn('追加: 1', summary)
    self.assertIn('aws_instance.minecraft', summary)
    self.assertNotIn('never-publish-this', summary)

  def test_replacement_warning(self):
    summary = plan.summarize(self.change(actions=['delete', 'create']))
    self.assertIn('置き換え', summary)
    self.assertIn('削除: 1', summary)

  def test_noop_and_data_sources_excluded(self):
    self.assertNotIn('aws_instance.minecraft', plan.summarize(self.change(actions=['no-op'])))
    self.assertNotIn('aws_instance.minecraft', plan.summarize(self.change(mode='data')))

  def test_string_index_redacted(self):
    summary = plan.summarize(self.change('aws_iam_role.app["private-role"]'))
    self.assertNotIn('private-role', summary)
    self.assertIn('[redacted]', summary)

  def test_secret_in_address_redacted(self):
    self.assertNotIn('private_role', plan.summarize(self.change('aws_iam_role.private_role'), ['private_role']))

  def test_unsafe_address_rejected(self):
    with self.assertRaises(ValueError):
      plan.summarize(self.change('aws_instance.bad`\n::warning::injection'))

  def test_unknown_action_rejected(self):
    with self.assertRaises(ValueError):
      plan.summarize(self.change(actions=['unexpected']))

  def test_incomplete_plan_rejected(self):
    for key in ({'errored': True}, {'complete': False}):
      with self.assertRaises(ValueError):
        plan.summarize({'format_version': '1.2', **key})

  def test_empty_plan(self):
    self.assertIn('追加: 0 / 変更: 0 / 削除: 0', plan.summarize({'format_version': '1.2'}))

  def test_malformed_or_deferred_plan(self):
    for value in ({}, [], {'format_version': '2.0'},
            {'format_version': '1.2', 'deferred_changes': [{}]}):
      with self.assertRaises(ValueError):
        plan.summarize(value)


class Diagnostics(unittest.TestCase):
  def test_runtime_failure_never_includes_exception_text(self):
    secret = 'arn:aws:iam::' + '987654' + '321098' + ':role/private'
    with self.assertRaises(plan.PlanFailure) as failure:
      with plan.step('plan'):
        raise RuntimeError(secret)
    self.assertEqual(failure.exception.diagnostic(), 'phase=plan; error=RuntimeError')
    self.assertNotIn(secret, str(failure.exception))
    self.assertFalse(check.findings(failure.exception.diagnostic()))

  def test_http_failure_only_includes_status(self):
    error = urllib.error.HTTPError('https://private.invalid/secret', 403, 'private-message', {}, None)
    with self.assertRaises(plan.PlanFailure) as failure:
      with plan.step('pr-comment'):
        raise error
    self.assertEqual(failure.exception.diagnostic(), 'phase=pr-comment; error=HTTPError; HTTP 403')

  def test_json_failure_never_includes_input(self):
    with self.assertRaises(plan.PlanFailure) as failure:
      with plan.step('show'):
        plan.json.loads('private-json-input')
    self.assertEqual(failure.exception.diagnostic(), 'phase=show; error=JSONDecodeError')

  def test_unknown_labels_are_not_printed(self):
    error = type('private_error_name', (Exception,), {})('private-message')
    failure = plan.PlanFailure('private-phase', error)
    self.assertEqual(failure.diagnostic(), 'phase=unknown; error=Unknown')

  def test_successful_step_continues(self):
    with plan.step('summary'):
      result = plan.summarize({'format_version': '1.2'})
    self.assertIn('追加: 0', result)

  def test_terraform_failure_only_exposes_known_api_and_error_labels(self):
    private = 'arn:aws:iam::' + '987654' + '321098' + ':role/private-role'
    error = plan.TerraformCommandFailure('Error acquiring the state lock: operation error S3: PutObject, '
      'api error AccessDenied: ' + private)
    failure = plan.PlanFailure('plan', error)
    self.assertEqual(failure.diagnostic(),
      'phase=plan; error=TerraformCommandFailure; aws=S3:PutObject; code=AccessDenied; reason=state-lock')
    self.assertNotIn(private, str(error))
    self.assertFalse(check.findings(failure.diagnostic()))

  def test_terraform_failure_drops_unknown_operation_names_and_values(self):
    error = plan.TerraformCommandFailure('operation error S3: PrivateIdentifier\nprivate-message')
    self.assertEqual(error.diagnostic(), '; aws=Unknown; code=Unknown; reason=Unknown')

  def test_global_budget_read_failure_has_public_operation_label(self):
    error = plan.TerraformCommandFailure('operation error Budgets: ListTagsForResource, '
      'api error AccessDeniedException: private-budget-name')
    self.assertEqual(error.diagnostic(),
      '; aws=Budgets:ListTagsForResource; code=AccessDeniedException; reason=Unknown')


class ClientGuide(unittest.TestCase):
  def settings(self, **changes):
    mod = {'url': 'https://example.com/mod.jar', 'sha256': '0' * 64, 'version': '1.2.3'}
    return {'version': '26.3', 'loader': 'fabric', 'loader_version': '0.17.3', 'mods': [
      {**mod, 'name': 'client-b', 'side': 'client'}, {**mod, 'name': 'client-c', 'side': 'both'},
      {**mod, 'name': 'client-a', 'side': 'both'}, {**mod, 'name': 'server-only', 'side': 'server'},
    ], **changes}

  def test_lists_client_mods_and_versions_without_server_only_mods(self):
    guide = client_guide.render(self.settings())
    for name in ('client-a', 'client-b', 'client-c'):
      self.assertIn(f'| {name} | `1.2.3` |', guide)
    self.assertNotIn('server-only', guide)
    self.assertIn('| Minecraft | `26.3` |', guide)
    self.assertIn('Fabric `0.17.3`', guide)

  def test_vanilla_guide_needs_no_loader_or_mods(self):
    guide = client_guide.render(self.settings(loader='vanilla', loader_version=None, mods=[]))
    self.assertIn('なし（バニラ）', guide)
    self.assertNotIn('`mods` フォルダー', guide)

  def test_committed_guide_matches_settings(self):
    self.assertEqual(client_guide.main(['--check']), 0)

  def test_check_fails_when_guide_differs(self):
    original = client_guide.render
    client_guide.render = lambda _settings: 'changed'
    try:
      self.assertEqual(client_guide.main(['--check']), 1)
    finally:
      client_guide.render = original


class RuntimeTags(unittest.TestCase):
  def test_terraform_ignores_tags_managed_at_runtime(self):
    source = (ROOT / 'modules/minecraft_server/main.tf').read_text(encoding='utf-8')
    self.assertIn('ignore_changes = [ami, tags["mc:stopping"], tags["mc:mode"]]', source)

if __name__ == '__main__':
  unittest.main()
