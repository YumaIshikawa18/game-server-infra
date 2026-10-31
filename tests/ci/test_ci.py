import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts/ci' / f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


check = load('check')
plan = load('plan')


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


if __name__ == '__main__':
    unittest.main()
