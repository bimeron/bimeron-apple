"""Pure offline proposal; maintenance_* Core APIs do not exist in current Core.

All evidence is injected synthetic input, never a live OS/security assertion.
Snapshots model atomic durable records, not filesystem flush/power-loss semantics.
"""
from copy import deepcopy
from dataclasses import dataclass, replace


class Blocked(Exception):
    pass


class Crash(Exception):
    pass


def require(condition, reason):
    if not condition:
        raise Blocked(reason)


@dataclass(frozen=True)
class Identity:
    installation: str
    operation: str
    generation: int
    boot: str
    instance: str
    session: str  # Explicit "idle" is required, never missing.


@dataclass(frozen=True)
class Artifact:
    digest: str
    parts: tuple
    trusted: bool = True
    compatible: bool = True
    protected: bool = True
    downgrade_allowed: bool = True

    def validate(self, lane):
        require(self.parts == ('binary', 'plist', 'metadata'), 'incomplete set')
        require(self.protected and self.compatible and self.downgrade_allowed,
                'artifact policy')
        require(lane == 'dev' or self.trusted, 'untrusted release')


@dataclass(frozen=True)
class Receipt:
    identity: Identity
    durable: bool = True
    authenticated: bool = True
    disconnected: bool = True
    inactive: bool = True
    recovered: bool = False
    producer_boot: str = None
    producer_instance: str = None


@dataclass(frozen=True)
class Ready:
    identity: Identity
    request: str
    digest: str
    authenticated: bool = True
    process_matches: bool = True
    capabilities: bool = True
    recovered: bool = True
    inactive: bool = True


class Model:
    """Separate root owner and explicit root CLI, represented only symbolically."""

    def __init__(self, artifact=None, *, capable=True):
        self.disk = dict(schema=1, installation='install', generation=0,
                         phase='idle', transaction=None, history={}, artifact=artifact,
                         backup=None, dirty=False, removed=False, tool=True,
                         profiles=('profile',), capable=capable,
                         lock_inode='fixed-lock', binding=(501, 'account-A'))
        self.boot = 'boot-1'
        self.instance = 'core-1'
        self.session = 'idle'
        self.holder = None
        self.sealed = False
        self.observer = None
        self.exit = None
        self.ready = None
        self.manual = False
        self.used_requests = set()
        self.events = []
        self.fault = None  # Optional (write label, before/after) one-shot fault.

    def snapshot(self):
        return deepcopy(self.disk)

    def write(self, label, fault=None, **changes):
        if self.fault is not None and self.fault[0] == label:
            _, fault = self.fault
            self.fault = None
        require(fault in (None, 'before', 'after'), 'fault boundary')
        if fault == 'before':
            self.crash()
            raise Crash(label + ':before')
        self.disk = dict(self.disk, **deepcopy(changes))
        t = self.disk['transaction']
        if t is not None:
            history = dict(self.disk['history'])
            history[t['identity'].operation] = dict(request=t['request'],
                identity=t['original_identity'], phase=self.disk['phase'])
            self.disk = dict(self.disk, history=history)
        self.events.append(label)
        if fault == 'after':
            self.crash()
            raise Crash(label + ':after')

    def crash(self):
        self.holder = self.observer = self.exit = self.ready = None
        self.manual = (self.disk['transaction'] is not None and
                       self.disk['phase'] not in ('released', 'removed', 'finalized'))
        # Core seal survives owner death; observer does not.

    def reboot(self, boot):
        require(boot != self.boot, 'same boot')
        self.crash()
        self.boot, self.instance, self.session = boot, 'recovery-core', 'idle'
        self.sealed = False

    def acquire(self, owner, uid=0, cli=True, inode='fixed-lock', protected=True,
                binding=(501, 'account-A')):
        require(uid == 0 and cli, 'explicit root CLI required')
        require(self.disk['schema'] == 1 and self.disk['capable'], 'unsupported install')
        require(protected and inode == self.disk['lock_inode'], 'lock substitution')
        require(binding == self.disk['binding'], 'account binding changed')
        require(self.holder in (None, owner), 'busy')
        self.holder = owner

    def owned(self):
        require(self.holder is not None and not self.manual, 'manual root resume required')

    def identity(self):
        t = self.disk['transaction']
        require(t is not None, 'no operation')
        return t['identity']

    def begin(self, operation, generation, action, candidate=None, lane='release',
              expected=None, absent=False, fault=None):
        self.owned()
        require(action in ('install', 'update', 'remove'), 'unsupported action/self-update')
        require(lane in ('dev', 'release'), 'unknown lane')
        request = (generation, action, candidate, lane, expected, absent)
        prior = self.disk['history'].get(operation)
        if prior is not None:
            require(request == prior['request'], 'conflicting operation reuse')
            return prior['identity']
        t = self.disk['transaction']
        require(t is None or self.disk['phase'] == 'released', 'unrelated operation/replay')
        require(generation == self.disk['generation'], 'stale generation')
        require(not self.disk['removed'], 'removed installation')
        require((action == 'install') == (self.disk['artifact'] is None), 'fresh-only install')
        require(action != 'install' or (absent and not self.disk['dirty']), 'residue/absence unknown')
        if action != 'remove':
            require(candidate is not None, 'candidate missing')
            candidate.validate(lane)
        identity = Identity(self.disk['installation'], operation, generation + 1,
                            self.boot, self.instance, self.session)
        require(expected == (self.instance, self.session), 'interruption consent mismatch')
        t = dict(identity=identity, action=action, candidate=candidate, lane=lane,
                 receipt=None, ran=False, fresh=action == 'install', disabled=False,
                 prior=self.disk['artifact'], selection='candidate', request=request,
                 original_identity=identity)
        self.write('gate', fault, transaction=t, phase='gated', generation=generation + 1)
        return identity

    def outcome(self, operation):
        require(operation in self.disk['history'], 'unknown operation')
        return deepcopy(self.disk['history'][operation])

    def start(self, uid=501, binding=(501, 'account-A'), legacy=False, fault=None):
        require(uid in (0, self.disk['binding'][0]) and binding == self.disk['binding'],
                'control policy')
        require(self.disk['schema'] == 1 and self.disk['capable'] and
                self.disk['artifact'] is not None and not self.disk['removed'] and
                not self.disk['dirty'] and not self.sealed and
                self.disk['phase'] in ('idle', 'released'), 'start fenced')
        # Dirty evidence must precede even a legacy start's resource mutation.
        self.write('dirty-before-start', fault, dirty=True)
        self.session = 'session-active'

    def shutdown(self, identity, *, disabled, cleanup=True, fault=None):
        self.owned()
        require(self.disk['phase'] in ('gated', 'verifying', 'rollback-pending'), 'shutdown phase')
        require(identity == self.identity() and
                (identity.boot, identity.instance, identity.session) ==
                (self.boot, self.instance, self.session), 'stale shutdown')
        self.observer = identity
        self.sealed = True
        self.events.append('seal-before-stop')
        t = dict(self.disk['transaction'], disabled=disabled)
        if not cleanup:
            self.write('cleanup-failed', fault, transaction=t, phase='blocked')
            return
        t['receipt'] = Receipt(identity)
        self.write('cleanup-receipt', fault, transaction=t, phase='stopped', dirty=False)
        self.session = 'idle'

    def observe_exit(self, identity):
        require(self.observer == identity and identity == self.identity(), 'exit observer lost/stale')
        self.exit = identity

    def clean(self, receipt=None, restart_excluded=False):
        t = self.disk['transaction']
        r = receipt or t['receipt']
        require(r is not None and r.identity == t['identity'] and r.durable and
                r.authenticated and r.disconnected and r.inactive, 'cleanup unproven')
        if r.recovered:
            require((r.producer_boot, r.producer_instance) ==
                    (self.boot, self.instance), 'stale recovery producer')
        require(t['disabled'] or restart_excluded, 'restart exclusion unproven')
        require(self.exit == r.identity or
                (r.recovered and self.boot != r.identity.boot), 'full exit unproven')

    def resume(self, *, approved=False, recovery=None, restart_excluded=False, fault=None):
        require(self.holder is not None and approved, 'explicit root resume')
        require(self.manual and self.disk['transaction'] is not None, 'not interrupted')
        t = self.disk['transaction']
        if self.disk['phase'] == 'committed':
            self.manual = False
            return
        if not t['fresh'] or t['ran']:
            require(self.boot != t['identity'].boot, 'no same-boot adoption')
            require(recovery is not None and recovery.recovered, 'Core recovery required')
            self.clean(recovery, restart_excluded)
            t = dict(t, receipt=recovery, disabled=t['disabled'] or restart_excluded)
        phase = 'stopped' if t['ran'] or not t['fresh'] else self.disk['phase']
        self.write('resume', fault, transaction=t, phase=phase)
        self.manual = False

    def publish(self, *, fault=None, partial=False):
        self.owned()
        t = self.disk['transaction']
        require(t is not None and self.disk['phase'] in ('gated', 'stopped', 'replacing'), 'publish phase')
        require(t['action'] != 'remove', 'removal is separate')
        if not t['fresh'] or t['ran']:
            self.clean()
        t['candidate'].validate(t['lane'])
        previous = t['prior']
        self.write('replace-intent', fault, phase='replacing', backup=previous)
        # A partial set is durable but cannot run or commit.
        artifact = replace(t['candidate'], parts=('binary',)) if partial else t['candidate']
        self.write('publish-set', artifact=artifact,
                   backup=previous)

    def launch(self, instance, request):
        self.owned()
        require(self.disk['phase'] == 'replacing', 'launch phase')
        t = self.disk['transaction']
        require(self.disk['artifact'] == t['candidate'], 'mixed artifact set')
        self.disk['artifact'].validate(t['lane'])
        require(request not in self.used_requests, 'readiness replay')
        self.used_requests.add(request)
        identity = replace(t['identity'], boot=self.boot, instance=instance, session='idle')
        # Intent conservatively means the candidate may run, even before enable/start.
        t = dict(t, identity=identity, ran=True, receipt=None, disabled=False)
        self.write('launch-intent', transaction=t, phase='launching')
        self.observer = self.exit = None
        self.instance, self.session = instance, 'idle'
        self.write('candidate-run', transaction=t, phase='verifying')
        self.observer = self.exit = None
        self.ready = (identity, request)

    def commit(self, evidence, fault=None):
        self.owned()
        require(self.disk['phase'] == 'verifying' and self.ready ==
                (evidence.identity, evidence.request), 'stale readiness')
        require(evidence.digest == self.disk['artifact'].digest and
                all((evidence.authenticated, evidence.process_matches,
                     evidence.capabilities, evidence.recovered, evidence.inactive)), 'not ready')
        self.disk['artifact'].validate(self.disk['transaction']['lane'])
        self.write('commit', fault, phase='committed', dirty=False)

    def release(self, identity):
        self.owned()
        require(self.disk['phase'] == 'committed' and identity == self.identity() and
                self.ready is not None and self.ready[0] == identity and
                (identity.boot, identity.instance) == (self.boot, self.instance), 'release requires fresh committed identity')
        self.write('release', phase='released')
        self.sealed = False
        self.holder = None

    def refresh_committed(self, evidence):
        self.owned()
        require(self.disk['phase'] == 'committed', 'not committed')
        require(evidence.identity == self.identity() and evidence.request not in self.used_requests
                and (evidence.identity.boot, evidence.identity.instance) == (self.boot, self.instance)
                and evidence.digest == self.disk['artifact'].digest and
                all((evidence.authenticated, evidence.process_matches, evidence.capabilities,
                     evidence.recovered, evidence.inactive)), 'fresh reconciliation required')
        self.used_requests.add(evidence.request)
        self.ready = (evidence.identity, evidence.request)

    def rollback(self, backup, *, fault=None, trust_valid=True, downgrade_valid=True):
        self.owned()
        t = self.disk['transaction']
        require(t is not None and t['ran'] and self.disk['phase'] == 'stopped', 'candidate cleanup required')
        self.clean()
        require(backup == self.disk['backup'], 'backup substitution')
        require(backup is not None, 'no backup')
        require(trust_valid and downgrade_valid, 'rollback revalidation failed')
        backup.validate(t['lane'])
        self.write('rollback-selection', fault, transaction=dict(t, candidate=backup, selection='rollback'), phase='replacing')
        self.write('rollback-set', artifact=backup)

    def remove(self, *, absent=False, fault=None):
        self.owned()
        require(self.disk['phase'] == 'stopped' and self.disk['transaction']['action'] == 'remove', 'remove phase')
        self.clean()
        require(absent, 'service absence required')
        self.write('core-removed', fault, artifact=None, backup=None, removed=True, phase='removed')

    def finalize(self, *, uid=0, approved=False, owner_exited=False, absent=False):
        require(uid == 0 and approved and owner_exited and absent and
                self.disk['phase'] == 'removed', 'separate external finalization required')
        self.write('tool-removed', tool=False, phase='finalized')
