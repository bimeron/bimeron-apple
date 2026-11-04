"""Deterministic synthetic evidence tests; no platform adapters or subprocesses."""
import unittest
from dataclasses import replace
from model import Artifact, Blocked, Crash, Identity, Model, Ready, Receipt


OLD = Artifact('old', ('binary', 'plist', 'metadata'))
NEW = replace(OLD, digest='new')


class ProtocolTests(unittest.TestCase):
    def model(self):
        m = Model(OLD)
        m.acquire('owner')
        return m

    def begin(self, m, **kwargs):
        return m.begin('op', 0, 'update', NEW, expected=(m.instance, m.session), **kwargs)

    def stopped(self, m):
        i = self.begin(m)
        m.shutdown(i, disabled=True)
        m.observe_exit(i)
        return i

    def verifying(self, m):
        self.stopped(m)
        m.publish()
        m.launch('candidate', 'request')
        return Ready(m.identity(), 'request', 'new')

    def blocked(self, call):
        with self.assertRaises(Blocked):
            call()

    def test_success_commit_release_and_one_backup(self):
        m = self.model()
        r = self.verifying(m)
        self.blocked(lambda: m.start(legacy=True))
        self.blocked(lambda: m.release(m.identity()))
        m.commit(r)
        m.release(m.identity())
        m.start()
        self.assertEqual(m.session, 'session-active')
        self.assertEqual(m.disk['backup'], OLD)
        m.acquire('owner')
        i = m.begin('next', 1, 'update', replace(NEW, digest='third'),
                    expected=(m.instance, m.session))
        m.shutdown(i, disabled=True)
        m.observe_exit(i)
        m.publish()
        self.assertEqual(m.disk['backup'], NEW)

    def test_root_cli_lock_and_binding(self):
        for kwargs in ({'uid': 501}, {'cli': False}, {'inode': 'new-lock'},
                       {'protected': False}, {'binding': (501, 'reused')}):
            m = Model(OLD)
            self.blocked(lambda: m.acquire('bad', **kwargs))
        m = self.model()
        self.blocked(lambda: m.acquire('competitor'))
        m.crash()
        m.acquire('competitor')
        self.assertEqual(m.disk['lock_inode'], 'fixed-lock')

    def test_control_uid_and_dirty_boot_fence(self):
        m = Model(OLD)
        self.blocked(lambda: m.start(uid=502))
        self.blocked(lambda: m.start(binding=(501, 'reused')))
        m.start(legacy=True)
        m.reboot('boot-2')
        self.blocked(lambda: m.start())
        self.assertEqual(m.session, 'idle')

    def test_missing_corrupt_legacy_and_removal_gate(self):
        for changes in ({'schema': None}, {'schema': 99}, {'capable': False},
                        {'artifact': None}, {'phase': 'removed'}, {'dirty': True}):
            for legacy in (False, True):
                m = Model(OLD)
                m.disk.update(changes)
                self.blocked(lambda: m.start(legacy=legacy))

    def test_gate_before_shutdown_and_seal_before_failed_stop(self):
        m = self.model()
        i = self.begin(m)
        for legacy in (False, True):
            self.blocked(lambda: m.start(legacy=legacy))
        m.shutdown(i, disabled=True, cleanup=False)
        self.assertLess(m.events.index('gate'), m.events.index('seal-before-stop'))
        self.blocked(m.publish)
        self.blocked(lambda: m.start(legacy=True))
        self.assertEqual(m.disk['artifact'], OLD)

    def test_start_race_requires_new_exact_consent(self):
        m = self.model()
        observed = (m.instance, m.session)
        m.start()
        self.blocked(lambda: m.begin('op', 0, 'update', NEW, expected=observed))
        i = self.begin(m)
        m.session = 'unexpected-session'
        self.blocked(lambda: m.shutdown(i, disabled=True))
        self.assertEqual(m.session, 'unexpected-session')
        self.blocked(lambda: m.start())

    def test_exact_shutdown_identity_every_dimension(self):
        for field, value in dict(installation='other', operation='other', generation=9,
                                 boot='other', instance='other', session='other').items():
            m = self.model()
            i = self.begin(m)
            self.blocked(lambda: m.shutdown(replace(i, **{field: value}), disabled=True))
            self.blocked(m.publish)

    def test_cleanup_and_full_exit_are_independent(self):
        m = self.model()
        i = self.begin(m)
        m.shutdown(i, disabled=True)
        self.blocked(m.publish)
        self.blocked(lambda: m.observe_exit(replace(i, instance='reused-pid')))
        m.observe_exit(i)
        for field in ('durable', 'authenticated', 'disconnected', 'inactive'):
            self.blocked(lambda: m.clean(replace(Receipt(i), **{field: False})))
        for field, value in dict(installation='x', operation='x', generation=8,
                                 boot='x', instance='x', session='x').items():
            self.blocked(lambda: m.clean(Receipt(replace(i, **{field: value}))))
        m.publish()
        self.assertEqual(m.disk['artifact'], NEW)

    def test_disable_is_not_exit_or_cleanup(self):
        m = self.model()
        i = self.begin(m)
        m.shutdown(i, disabled=False)
        m.observe_exit(i)
        self.blocked(m.publish)

    def test_duplicate_timeout_query_and_unrelated_replay(self):
        m = self.model()
        i = self.begin(m)
        self.assertEqual(self.begin(m), i)
        self.blocked(lambda: m.begin('other', 0, 'update', NEW, expected=('core-1', 'idle')))
        self.blocked(lambda: m.begin('op', 0, 'remove', expected=('core-1', 'idle')))
        self.assertEqual(m.identity(), i)

    def test_artifact_lane_and_unsupported_actions(self):
        for candidate in (replace(NEW, trusted=False), replace(NEW, compatible=False),
                          replace(NEW, protected=False), replace(NEW, parts=('binary',))):
            m = self.model()
            self.blocked(lambda: m.begin('op', 0, 'update', candidate,
                                        expected=('core-1', 'idle')))
        m = self.model()
        self.blocked(lambda: m.begin('op', 0, 'self-update', expected=('core-1', 'idle')))
        dev = replace(NEW, trusted=False)
        m.begin('op', 0, 'update', dev, lane='dev', expected=('core-1', 'idle'))
        i = m.identity()
        m.shutdown(i, disabled=True)
        m.observe_exit(i)
        m.publish()
        m.launch('dev-core', 'r')
        m.commit(Ready(m.identity(), 'r', 'new'))
        m.release(m.identity())
        self.assertFalse(m.disk['artifact'].trusted)
        self.blocked(lambda: m.disk['artifact'].validate('release'))

    def test_partial_set_never_launches(self):
        m = self.model()
        self.stopped(m)
        m.publish(partial=True)
        self.blocked(lambda: m.launch('candidate', 'r'))
        self.blocked(lambda: m.start())
        m.publish()
        m.launch('candidate', 'r')
        self.assertEqual(m.disk['backup'], OLD)

    def test_fresh_install_requires_positive_absence(self):
        m = Model()
        m.acquire('owner')
        self.blocked(lambda: m.begin('op', 0, 'install', NEW, expected=('core-1', 'idle')))
        m.begin('op', 0, 'install', NEW, expected=('core-1', 'idle'), absent=True)
        m.publish()
        m.launch('new', 'r')
        m.commit(Ready(m.identity(), 'r', 'new'))
        m.release(m.identity())
        m.start()

    def test_readiness_replay_mismatch_and_failed_evidence(self):
        for field, value in dict(request='cached', digest='wrong', authenticated=False,
                                 process_matches=False, capabilities=False,
                                 recovered=False, inactive=False).items():
            m = self.model()
            r = self.verifying(m)
            self.blocked(lambda: m.commit(replace(r, **{field: value})))
            self.blocked(lambda: m.release(m.identity()))
        m = self.model()
        r = self.verifying(m)
        self.blocked(lambda: m.commit(replace(r, identity=replace(r.identity, boot='old'))))

    def test_owner_crash_requires_manual_reboot_and_recovery(self):
        m = self.model()
        i = self.stopped(m)
        m.crash()
        m.acquire('replacement')
        self.blocked(m.publish)
        self.blocked(lambda: m.resume(approved=True, recovery=Receipt(i, recovered=True, producer_boot=m.boot, producer_instance=m.instance), restart_excluded=True))
        self.blocked(lambda: m.observe_exit(i))
        m.reboot('boot-2')
        m.acquire('replacement')
        self.blocked(lambda: m.resume(approved=False, recovery=Receipt(i, recovered=True, producer_boot=m.boot, producer_instance=m.instance), restart_excluded=True))
        self.blocked(lambda: m.resume(approved=True))
        m.resume(approved=True, recovery=Receipt(i, recovered=True, producer_boot=m.boot, producer_instance=m.instance), restart_excluded=True)
        m.publish()
        self.assertEqual(m.disk['artifact'], NEW)
        self.blocked(lambda: m.start())

    def test_rollback_requires_candidate_cleanup_and_revalidation(self):
        m = self.model()
        self.verifying(m)
        self.blocked(lambda: m.rollback(OLD))
        i = m.identity()
        m.shutdown(i, disabled=True)
        self.blocked(lambda: m.rollback(OLD))
        m.observe_exit(i)
        self.blocked(lambda: m.rollback(OLD, trust_valid=False))
        self.blocked(lambda: m.rollback(OLD, downgrade_valid=False))
        self.blocked(lambda: m.rollback(replace(OLD, digest='substituted')))
        self.assertEqual(m.disk['artifact'], NEW)
        m.rollback(OLD)
        self.blocked(lambda: m.launch('rollback', 'request'))
        m.launch('rollback', 'fresh-request')
        m.commit(Ready(m.identity(), 'fresh-request', 'old'))
        m.release(m.identity())
        m.start()

    def test_two_stage_remove_retains_profiles(self):
        m = self.model()
        i = m.begin('remove', 0, 'remove', expected=('core-1', 'idle'))
        self.blocked(lambda: m.remove(absent=True))
        m.shutdown(i, disabled=True)
        m.observe_exit(i)
        self.blocked(m.remove)
        m.remove(absent=True)
        self.assertTrue(m.disk['tool'])
        self.blocked(lambda: m.start())
        self.blocked(lambda: m.finalize(approved=True, absent=True))
        m.finalize(approved=True, owner_exited=True, absent=True)
        self.assertEqual(m.disk['profiles'], ('profile',))
        self.assertFalse(m.disk['tool'])

    def test_gate_crash_boundaries_snapshots(self):
        for fault in ('before', 'after'):
            m = self.model()
            before = m.snapshot()
            with self.assertRaises(Crash):
                self.begin(m, fault=fault)
            if fault == 'before':
                self.assertEqual(m.disk, before)
            else:
                self.assertNotEqual(m.disk, before)
                self.assertEqual(m.disk['phase'], 'gated')
            if fault == 'before':
                m.start()
            else:
                self.blocked(lambda: m.start(legacy=True))
                m.acquire('replacement')
                self.blocked(m.publish)

    def test_receipt_crash_boundaries_never_invent_exit(self):
        for fault in ('before', 'after'):
            m = self.model()
            i = self.begin(m)
            with self.assertRaises(Crash):
                m.shutdown(i, disabled=True, fault=fault)
            self.assertEqual(m.disk['transaction']['receipt'] is not None, fault == 'after')
            m.acquire('replacement')
            self.blocked(m.publish)
            self.blocked(lambda: m.observe_exit(i))

    def test_commit_crash_before_after_and_release_reconciliation(self):
        for fault in ('before', 'after'):
            m = self.model()
            r = self.verifying(m)
            with self.assertRaises(Crash):
                m.commit(r, fault=fault)
            m.acquire('replacement')
            self.blocked(lambda: m.release(m.identity()))
            self.blocked(lambda: m.start())
            if fault == 'after':
                m.resume(approved=True)
                self.blocked(lambda: m.refresh_committed(r))
                m.refresh_committed(replace(r, request='fresh-reconcile'))
                m.release(m.identity())
                m.start()
            else:
                self.blocked(lambda: m.resume(approved=True))

    def test_replace_and_remove_intent_crashes_keep_fence(self):
        for fault in ('before', 'after'):
            m = self.model()
            self.stopped(m)
            with self.assertRaises(Crash):
                m.publish(fault=fault)
            self.assertEqual(m.disk['artifact'], OLD)
            self.blocked(lambda: m.start())
            m = self.model()
            i = m.begin('remove', 0, 'remove', expected=('core-1', 'idle'))
            m.shutdown(i, disabled=True)
            m.observe_exit(i)
            with self.assertRaises(Crash):
                m.remove(absent=True, fault=fault)
            self.assertEqual(m.disk['artifact'], OLD if fault == 'before' else None)
            self.assertEqual(m.disk['profiles'], ('profile',))
            self.blocked(lambda: m.start())


    def test_all_remaining_durable_write_crash_boundaries(self):
        # Every modeled durable publication is interrupted on both sides.
        for label in ('dirty-before-start', 'cleanup-failed', 'publish-set',
                      'candidate-run', 'release', 'rollback-selection',
                      'rollback-set', 'resume', 'tool-removed'):
            for boundary in ('before', 'after'):
                with self.subTest(label=label, boundary=boundary):
                    m = self.model()
                    if label == 'dirty-before-start':
                        action = m.start
                    elif label == 'cleanup-failed':
                        i = self.begin(m)
                        action = lambda: m.shutdown(i, disabled=True, cleanup=False)
                    elif label == 'publish-set':
                        self.stopped(m)
                        action = m.publish
                    elif label == 'candidate-run':
                        self.stopped(m)
                        m.publish()
                        action = lambda: m.launch('candidate', 'r')
                    elif label == 'release':
                        r = self.verifying(m)
                        m.commit(r)
                        action = lambda: m.release(m.identity())
                    elif label in ('rollback-selection', 'rollback-set'):
                        self.verifying(m)
                        i = m.identity()
                        m.shutdown(i, disabled=True)
                        m.observe_exit(i)
                        action = lambda: m.rollback(OLD)
                    elif label == 'resume':
                        i = self.stopped(m)
                        m.reboot('boot-2')
                        m.acquire('replacement')
                        action = lambda: m.resume(approved=True, recovery=Receipt(i, recovered=True, producer_boot=m.boot, producer_instance=m.instance), restart_excluded=True)
                    else:
                        i = m.begin('remove', 0, 'remove', expected=('core-1', 'idle'))
                        m.shutdown(i, disabled=True)
                        m.observe_exit(i)
                        m.remove(absent=True)
                        action = lambda: m.finalize(approved=True, owner_exited=True, absent=True)
                    snapshot = m.snapshot()
                    m.fault = (label, boundary)
                    with self.assertRaises(Crash):
                        action()
                    self.assertEqual(m.disk['profiles'], snapshot['profiles'])
                    if label == 'release' and boundary == 'after':
                        self.blocked(m.start)  # Core has not processed release yet.
                        m.reboot('boot-2')
                        m.start()
                    elif label == 'dirty-before-start' and boundary == 'before':
                        m.start()
                    else:
                        self.blocked(lambda: m.start(legacy=True))
                    if label == 'publish-set':
                        self.assertEqual(m.disk['artifact'], OLD if boundary == 'before' else NEW)
                    if label == 'rollback-set':
                        self.assertEqual(m.disk['artifact'], NEW if boundary == 'before' else OLD)

    def test_fresh_candidate_crash_cannot_skip_cleanup(self):
        m = Model()
        m.acquire('owner')
        m.begin('op', 0, 'install', NEW, expected=('core-1', 'idle'), absent=True)
        m.publish()
        m.launch('candidate', 'r')
        i = m.identity()
        m.crash()
        m.acquire('replacement')
        self.blocked(lambda: m.resume(approved=True))
        m.reboot('boot-2')
        m.acquire('replacement')
        self.blocked(lambda: m.resume(approved=True))
        # Even fresh installation must recover a candidate that has run.
        self.blocked(lambda: m.resume(approved=True, recovery=Receipt(i, recovered=True, producer_boot=m.boot, producer_instance=m.instance)))
        # Restart exclusion has not been observed for that candidate.
        self.blocked(m.publish)
        m.resume(approved=True, recovery=Receipt(i, recovered=True, producer_boot=m.boot, producer_instance=m.instance), restart_excluded=True)
        m.publish()
        self.assertEqual(m.disk['artifact'], NEW)

    def recovery(self, m, target):
        return Receipt(target, recovered=True, producer_boot=m.boot,
                       producer_instance=m.instance)

    def finish(self, m, digest, request='endpoint'):
        m.launch('endpoint-core', request)
        m.commit(Ready(m.identity(), request, digest))
        m.release(m.identity())
        self.assertEqual(m.disk['phase'], 'released')
        self.assertEqual(m.session, 'idle')

    def test_launch_intent_and_run_crashes_recover_to_endpoint(self):
        for fresh in (False, True):
            for label in ('launch-intent', 'candidate-run'):
                for boundary in ('before', 'after'):
                    with self.subTest(fresh=fresh, label=label, boundary=boundary):
                        m = Model() if fresh else Model(OLD)
                        m.acquire('owner')
                        if fresh:
                            m.begin('op', 0, 'install', NEW,
                                    expected=(m.instance, m.session), absent=True)
                        else:
                            self.stopped(m)
                        m.publish()
                        original_instance = m.instance
                        m.fault = (label, boundary)
                        with self.assertRaises(Crash):
                            m.launch('candidate', 'interrupted')
                        may_run = label != 'launch-intent' or boundary == 'after'
                        if label == 'launch-intent':
                            self.assertEqual(m.instance, original_instance)
                        self.assertEqual(m.disk['transaction']['ran'], may_run)
                        target = m.identity()
                        m.acquire('replacement')
                        if may_run or not fresh:
                            self.blocked(lambda: m.resume(approved=True))
                            self.blocked(m.publish)
                            m.reboot('boot-2')
                            m.acquire('replacement')
                            receipt = self.recovery(m, target)
                            if may_run:
                                self.assertFalse(m.disk['transaction']['disabled'])
                                self.blocked(lambda: m.resume(approved=True, recovery=receipt))
                            m.resume(approved=True, recovery=receipt, restart_excluded=True)
                        else:
                            m.resume(approved=True)
                        m.publish()
                        self.assertEqual(m.disk['backup'], None if fresh else OLD)
                        self.finish(m, 'new')
                        self.assertFalse(m.disk['transaction']['disabled'])

    def test_repeated_publication_preserves_prior_and_recovery_selection(self):
        for rollback in (False, True):
            for boundary in ('before', 'after'):
                with self.subTest(rollback=rollback, boundary=boundary):
                    m = self.model()
                    self.stopped(m)
                    m.publish()
                    if rollback:
                        m.launch('failed-core', 'failed')
                        target = m.identity()
                        m.shutdown(target, disabled=True)
                        m.observe_exit(target)
                        m.fault = ('rollback-selection', boundary)
                        with self.assertRaises(Crash):
                            m.rollback(OLD)
                    else:
                        m.crash()
                    selected_old = rollback and boundary == 'after'
                    for boot in ('boot-2', 'boot-3'):
                        target = m.identity()
                        m.reboot(boot)
                        m.acquire('replacement')
                        m.resume(approved=True, recovery=self.recovery(m, target),
                                 restart_excluded=True)
                        m.publish()
                        self.assertEqual(m.disk['backup'], OLD)
                        self.assertEqual(m.disk['artifact'], OLD if selected_old else NEW)
                        self.assertEqual(m.disk['transaction']['selection'],
                                         'rollback' if selected_old else 'candidate')
                    self.finish(m, 'old' if selected_old else 'new')
                    self.assertEqual(m.disk['backup'], OLD)

    def test_operation_history_queries_and_rejects_reuse(self):
        m = self.model()
        expected = (m.instance, m.session)
        original = self.begin(m)
        m.shutdown(original, disabled=True)
        m.observe_exit(original)
        m.publish()
        self.finish(m, 'new', 'first')
        m.acquire('owner')
        second_expected = (m.instance, m.session)
        third = replace(NEW, digest='third')
        i = m.begin('op-B', 1, 'update', third, expected=second_expected)
        m.shutdown(i, disabled=True)
        m.observe_exit(i)
        m.publish()
        self.finish(m, 'third', 'second')
        m.reboot('boot-2')
        m.acquire('query-owner')
        snapshot = m.snapshot()
        self.assertEqual(m.begin('op', 0, 'update', NEW, expected=expected), original)
        self.assertEqual(m.outcome('op')['phase'], 'released')
        self.assertEqual(m.outcome('op-B')['phase'], 'released')
        self.assertEqual(m.disk, snapshot)
        self.blocked(lambda: m.begin('op', 2, 'update', NEW,
                                    expected=(m.instance, m.session)))
        self.blocked(lambda: m.begin('op', 0, 'update', third, expected=expected))
        self.blocked(lambda: m.outcome('unknown'))

    def test_recovery_producer_and_original_target_binding(self):
        m = self.model()
        self.verifying(m)
        target = m.identity()
        m.reboot('boot-2')
        m.acquire('replacement')
        receipt = self.recovery(m, target)
        for bad in (replace(receipt, producer_boot='old'),
                    replace(receipt, producer_instance='other'),
                    replace(receipt, identity=replace(target, operation='other')),
                    replace(receipt, identity=replace(target, generation=99))):
            self.blocked(lambda: m.resume(approved=True, recovery=bad,
                                          restart_excluded=True))
        m.resume(approved=True, recovery=receipt, restart_excluded=True)
        m.reboot('boot-3')
        m.acquire('replacement')
        self.blocked(lambda: m.resume(approved=True, recovery=receipt,
                                      restart_excluded=True))
        self.blocked(m.publish)
        self.assertEqual(m.disk['backup'], OLD)
        m.resume(approved=True, recovery=self.recovery(m, target), restart_excluded=True)
        m.publish()
        self.finish(m, 'new')


if __name__ == '__main__':
    unittest.main()
