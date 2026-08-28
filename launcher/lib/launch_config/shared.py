from dataclasses import dataclass
from pathlib import Path

from launcher.lib.constants import WARN_PREFIX
from launcher.lib.host_state import GitState, HostState


@dataclass(frozen=True, kw_only=True)
class SandboxLaunchConfig:
    # Two segments because the declared environment is injected between them
    # by the stub; those values never enter Python.
    argv_before_env: tuple[str, ...]
    argv_after_env: tuple[str, ...]
    passwd: str
    ca_bundle: tuple[Path, ...]
    cleanup: tuple[Path, ...]
    # Removed only if still empty: content something wrote there in the
    # meantime is not ours to delete.
    cleanup_if_empty: tuple[Path, ...]
    warnings: tuple[str, ...]


def get_sessions_root_warnings(host: HostState, session_dir: Path) -> list[str]:
    # A warning rather than a refusal: an rwDir on $HOME/.local/state is a
    # plausible accident, and the sessions root is relocatable.
    sessions_root = session_dir.parent
    warnings = []
    for declared in host.declared:
        if declared.mode != "rw":
            continue
        if not sessions_root.is_relative_to(declared.expanded_path):
            continue
        warnings.append(
            f"{WARN_PREFIX} {declared.expanded_path} is declared read-write and "
            f"contains this sandbox's own session records ({sessions_root})."
        )
    return warnings


def _is_git_root_the_home(host: HostState, git: GitState) -> bool:
    # A home-rooted repo's object store holds the history of tracked
    # dotfiles. Launching from the home directory itself is the exception:
    # the user has already confirmed that the whole home is exposed.
    if host.real_home == git.repo_root:
        return host.cwd != host.real_home
    return git.repo_root in host.real_home.parents


def get_usable_git_state(host: HostState) -> tuple[GitState | None, list[str]]:
    if host.git is None:
        return None, []
    if _is_git_root_the_home(host, host.git):
        return None, [
            f"{WARN_PREFIX} git root resolves to your home directory "
            f"({host.real_home}), which the sandbox will not expose. "
            f"git is disabled for this session."
        ]
    return host.git, []
