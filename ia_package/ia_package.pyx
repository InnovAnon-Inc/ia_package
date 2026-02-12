#! /usr/bin/env python
# cython: language_level=3
# distutils: language=c++

# TODO need to support socks proxies as early as possible
# TODO resolve discrepancies between what *should* be .gitignore'd and what was maybe checked in before the file was updated
# TODO need to move version.py into a submodule
# TODO need to support targeting self & others
# TODO need to collect that perf data & merge the profiles
# TODO code cleanup, etc.

# TODO cflag method in setup.py
# - if we can do it reflectively, then that is the gold standard
# - otherwise, check whether we're installed. if we are, then the target setup.py can import the function from us. ofc, then the target pyproject.toml will also need to be informed.
# - if we're bundled and not installed, then packaging it as a data file would be the only way to get at that source code.

import ast
from contextlib  import ExitStack, contextmanager
from dataclasses import dataclass
import dis
import hashlib
import importlib
import inspect
from io          import StringIO
import logging
import multiprocessing
import os
from pathlib     import Path
import platform
import re
import shlex
import shutil
import socket
import subprocess
from subprocess  import Popen
import sys
import sysconfig
import time
import tomllib
from types       import *
from typing      import *

import build
import git
import github # FIXME unused ???? !!!!!!! how to create remote repo ?
import mdutils
import pipreqs
#import tomli
import tomli_w

##
#
##

# TODO check whether local & remote git repos exist.
# TODO if no remote and no local: create both. easy
# TODO if remote but no local: pull it down. easy
# TODO if local but no remote: creater the remote and push. easy
# TODO if local and remote: pull & push. if problems, abort. easy

##def ensure_synchronized_source(project_root: Path)->None:# | None = None) -> None:
##    """The clean entry point for the Bootstrapper's Git stage."""
##    import git
##    from git import Repo, InvalidGitRepositoryError
##
##    #project_root = project_root or Path().resolve()
##    branch = os.getenv('GIT_BRANCH', 'main')
##
##    # 1. Identity Discovery: Trust the disk first.
##    remote_url = None
##    try:
##        repo = git.Repo(project_root)
##        if 'origin' in repo.remotes:
##            remote_url = repo.remotes.origin.url
##            logging.info(f"✔ Found existing remote: {remote_url}")
##    except (git.InvalidGitRepositoryError, AttributeError) as e:
##        logging.error(e)
##        #pass #remote_url = None
##
##    # 2. Fallback: Only if disk discovery fails, use ENV or template
##    if not remote_url:
##        current_org = os.getenv('ORGANIZATION', 'InnovAnon-Inc')
##        remote_url = os.getenv('GIT_REMOTE_URL', 
##                               f'https://github.com/{current_org}/{project_root.stem}.git')
##        logging.info(f"ℹ Using discovered remote: {remote_url}")
##
##    # 3. Reconcile
##    _sync_repo(remote_url, project_root, branch)
##
##
#####def _sync_repo(remote_url: str, target_dir: Path, branch: str) -> None:
#####    """Makes the filesystem match the URL without corrupting existing configs."""
#####    from git import Repo, InvalidGitRepositoryError
#####
#####    if not target_dir.exists():
#####        target_dir.mkdir(parents=True)
#####
#####    try:
#####        repo = Repo(target_dir)
#####    except InvalidGitRepositoryError:
#####        logging.info(f"🗃 Initializing clone from {remote_url}")
#####        repo = Repo.clone_from(remote_url, target_dir)
#####
#####    # Remote Alignment: Only set if it's actually different to avoid config churn
#####    if 'origin' not in repo.remotes:
#####        repo.create_remote('origin', remote_url)
#####    else:
#####        origin = repo.remotes.origin
#####        if origin.url != remote_url:
#####            # SAFETY: If we already have a URL, don't overwrite it with a guess.
#####            # Only update if the user explicitly provided a new GIT_REMOTE_URL env var.
#####            explicit_remote = os.getenv('GIT_REMOTE_URL')
#####            if explicit_remote and origin.url != explicit_remote:
#####                logging.warning(f"🔄 Updating origin URL to {explicit_remote}")
#####                origin.set_url(explicit_remote)
#####
#####    # Synchronize
#####    origin = repo.remotes.origin
#####    origin.fetch()
#####
#####    # Branch Alignment
#####    try:
#####        if repo.active_branch.name != branch:
#####            logging.info(f"🔀 Switching to branch: {branch}")
#####            repo.git.checkout(branch)
#####    except TypeError: # Handle detached HEAD
#####        repo.git.checkout(branch)
#####
#####    # Only pull if we have an upstream set
#####    if repo.active_branch.tracking_branch():
#####        origin.pull(branch)
#####
#####    if repo.is_dirty():
#####        raise RuntimeError(f"Dirty repo at {target_dir}. Commit or stash changes before proceeding.")
####def _sync_repo(remote_url: str, target_dir: Path, branch: str) -> None:
####    """Adopt existing files or clone new ones without crashing."""
####    import git
####    from git import Repo, InvalidGitRepositoryError, GitCommandError
####
####    repo = None
####    if not target_dir.exists():
####        target_dir.mkdir(parents=True)
####
####    try:
####        # Try to open existing repo
####        repo = git.Repo(target_dir)
####        logging.info(f"✔ Attached to existing repo at {target_dir}")
####    except git.InvalidGitRepositoryError:
####        # If directory is not empty, we cannot clone. We must INIT and ADOPT.
####        if any(target_dir.iterdir()):
####            logging.info(f"✨ Adopting existing files in {target_dir} into new Git repo")
####            repo = git.Repo.init(target_dir)
####        else:
####            logging.info(f"🗃 Initializing clone from {remote_url}")
####            try:
####                repo = git.Repo.clone_from(remote_url, target_dir)
####            except git.GitCommandError as e:
####                logging.error(f"❌ Clone failed. Remote likely does not exist yet: {e}")
####                return # TODO the error is safe to ignore ?
####
####    # Remote Alignment
####    if 'origin' not in repo.remotes:
####        repo.create_remote('origin', remote_url)
####
####    origin = repo.remotes.origin
####
####    # Check if remote actually exists before fetching/pulling
####    try:
####        origin.fetch()
####    except git.GitCommandError as e:
####        logging.warning(f"⚠️ Remote 'origin' at {remote_url} is unreachable. Skipping network sync.")
####        #return # NOTE always fail fast ; never silently ignore. that's not how "error handling" works.
####        raise e
####
####    # Branch Alignment
####    try:
####        if repo.head.is_detached or repo.active_branch.name != branch:
####            logging.info(f"🔀 Switching to branch: {branch}")
####            repo.git.checkout(branch)
####    except (TypeError, git.GitCommandError) as e:
####        logging.error(e)
####        # Create branch if it doesn't exist locally
####        repo.git.checkout('-b', branch)
####
####    # Only pull if there is an upstream to pull from
####    try:
####        if repo.active_branch.tracking_branch():
####            origin.pull(branch)
####    except git.GitCommandError as e:
####        logging.error(f"❌ Pull failed: {e}")
####        raise e
####
####    if repo.is_dirty():
####        logging.warning(f"⚠️ Repo at {target_dir} is dirty. Proceeding with caution.")
###
###class AlwaysFailFastYouRetardedFuckingPieceOfShitException(Exception):
###    """ do you fucking get it yet """
###
###def _ensure_remote_repo_exists(remote_url: str) -> None:
###    """Uses the GitHub API to create the repository if it doesn't exist."""
###    import git
###    from github import Github, GithubException
###    token = os.getenv('GH_TOKEN')
###    if not token:
###        logging.error("❌ GH_TOKEN not found in environment. Cannot create remote repo.")
###        #return
###        raise AlwaysFailFastYouRetardedFuckingPieceOfShitException()
###
###    # Extract 'organization/repo' or 'user/repo' from URL
###    # e.g., https://github.com/InnovAnon-Inc/sad.git -> InnovAnon-Inc/sad
###    parts = remote_url.rstrip('.git').split('/')
###    repo_name = parts[-1]
###    org_name = parts[-2]
###
###    gh = Github(token)
###    try:
###        # Check if it's an Org or a User
###        try:
###            entity = gh.get_organization(org_name)
###        except GithubException:
###            entity = gh.get_user()
###
###        logging.info(f"🚀 Creating remote repository: {org_name}/{repo_name}")
###        entity.create_repo(
###            repo_name,
###            private=False,  # Adjust based on your needs
###            has_issues=True,
###            has_wiki=True
###        )
###        logging.info("✅ Remote repository created successfully.")
###    except GithubException as e:
###        if e.status == 422:
###            logging.info("ℹ️ Remote repository already exists on GitHub.")
###        else:
###            logging.error(f"❌ GitHub API Error: {e.data.get('message')}")
###            raise
###
###def _sync_repo(remote_url: str, target_dir: Path, branch: str) -> None:
###    """Adopt existing files, create remote if missing, and synchronize."""
###    repo = None
###    if not target_dir.exists():
###        target_dir.mkdir(parents=True)
###
###    # 1. Local Attachment/Initialization
###    try:
###        repo = git.Repo(target_dir)
###        logging.info(f"✔ Attached to existing repo at {target_dir}")
###    except git.InvalidGitRepositoryError:
###        if any(target_dir.iterdir()):
###            logging.info(f"✨ Adopting files in {target_dir}")
###            repo = git.Repo.init(target_dir)
###        else:
###            logging.info(f"🗃 Cloning from {remote_url}")
###            try:
###                repo = git.Repo.clone_from(remote_url, target_dir)
###            except git.GitCommandError:
###                # If clone fails, we might need to create it
###                _ensure_remote_repo_exists(remote_url)
###                repo = git.Repo.init(target_dir)
###
###    # 2. Remote Configuration
###    if 'origin' not in repo.remotes:
###        repo.create_remote('origin', remote_url)
###    origin = repo.remotes.origin
###
###    # 3. Network Sync with Auto-Creation Fallback
###    try:
###        origin.fetch()
###    except git.GitCommandError:
###        logging.warning("⚠️ Fetch failed. Attempting to create remote repository...")
###        _ensure_remote_repo_exists(remote_url)
###        origin.fetch()
###
###    # 4. Branch Alignment
###    try:
###        if repo.head.is_detached or repo.active_branch.name != branch:
###            logging.info(f"🔀 Switching to branch: {branch}")
###            repo.git.checkout(branch)
###    except (TypeError, git.GitCommandError):
###        logging.info(f"🌱 Creating new local branch: {branch}")
###        repo.git.checkout('-b', branch)
###
###    # 5. Pull and Track
###    try:
###        # Set upstream if not set
###        repo.git.branch(f'--set-upstream-to=origin/{branch}', branch)
###        origin.pull(branch)
###    except git.GitCommandError as e:
###        logging.warning(f"⚠️ Could not pull (possibly empty remote): {e}")
###
###    if repo.is_dirty():
###        logging.warning(f"⚠️ Repo at {target_dir} is dirty.")
def _ensure_remote_repo_exists(remote_url: str) -> None: # FIXME
    """Uses the GitHub API to create the repository if it doesn't exist."""
    token = os.getenv('GH_TOKEN')
    if not token:
        logging.error("❌ GH_TOKEN not found in environment. Cannot create remote repo.")
        # If we are here, we are about to crash.
        raise RuntimeError("Missing GH_TOKEN. Export it to allow remote creation.")

    # Parse 'InnovAnon-Inc/sad' from 'https://github.com/InnovAnon-Inc/sad.git'
    repo_path = remote_url.split('github.com/')[-1].replace('.git', '')
    org_name, repo_name = repo_path.split('/')

    from github import Github, GithubException
    gh = Github(auth=github.Auth.Token(token))

    try:
        try:
            entity = gh.get_organization(org_name)
            logging.info(f"🏢 Identified organization: {org_name}")
        except GithubException:
            entity = gh.get_user()
            logging.info(f"👤 Identified user: {entity.login}")

        logging.info(f"🚀 Attempting to create remote: {repo_path}")
        entity.create_repo(repo_name, private=False, has_issues=True)
        logging.info("✅ Remote repository created.")
    except GithubException as e:
        if e.status == 422: # Already exists
            logging.info("ℹ️ Remote already exists (422), likely a permission/visibility sync issue.")
        else:
            logging.error(f"❌ GitHub API Error ({e.status}): {e.data.get('message')}")
            raise
##def _sync_repo(remote_url: str, target_dir: Path, branch: str) -> None:
##    """Adopt local files, create remote, and synchronize."""
##    import git
##    from git import Repo, GitCommandError
##
##    repo = None
##    if not target_dir.exists():
##        target_dir.mkdir(parents=True)
##
##    try:
##        repo = git.Repo(target_dir)
##        logging.info(f"✔ Attached to existing repo at {target_dir}")
##    except git.InvalidGitRepositoryError:
##        if any(target_dir.iterdir()):
##            logging.info(f"✨ Adopting existing files into new Git repo")
##            repo = git.Repo.init(target_dir)
##        else:
##            logging.info(f"🗃 Cloning from {remote_url}")
##            try:
##                repo = git.Repo.clone_from(remote_url, target_dir)
##            except GitCommandError:
##                _ensure_remote_repo_exists(remote_url)
##                repo = git.Repo.init(target_dir)
##
##    if 'origin' not in repo.remotes:
##        repo.create_remote('origin', remote_url)
##    origin = repo.remotes.origin
##
##    # Try to fetch. If it fails, the remote is definitely missing.
##    try:
##        origin.fetch()
##    except GitCommandError:
##        logging.warning(f"⚠ Remote unreachable. Creating {remote_url}...")
##        _ensure_remote_repo_exists(remote_url)
##        origin.fetch()
##
##    # Branch Alignment
##    try:
##        if repo.head.is_detached or repo.active_branch.name != branch:
##            repo.git.checkout(branch)
##    except (TypeError, GitCommandError):
##        logging.info(f"🌱 Creating branch: {branch}")
##        repo.git.checkout('-b', branch)
##
####    # Final Sync
####    try:
####        repo.git.branch(f'--set-upstream-to=origin/{branch}', branch)
####        origin.pull(branch)
####    except GitCommandError as e:
####        logging.warning(f"⚠️ Could not pull (remote might be empty): {e}")
####
####    if repo.is_dirty():
####        logging.info("📝 Local changes detected. Provisioning complete.")
###    try:
###        # Try to link and pull
###        repo.git.branch(f'--set-upstream-to=origin/{branch}', branch)
###        origin.pull(branch)
###        logging.info("✅ Upstream synchronized.")
###    except git.GitCommandError as e:
###        if "no commit on branch" in str(e) or "upstream" in str(e):
###            logging.info("🌱 Remote is empty. Performing initial push to establish 'main'...")
###            # Ensure we have at least one commit locally to push
###            if not repo.heads:
###                 # If the repo is totally empty locally too, create a dummy or wait
###                 logging.warning("⚠️ Local repo has no commits to push.")
###            else:
###                # Force push the current branch to origin and set upstream (-u)
###                repo.git.push('-u', 'origin', branch)
###                logging.info(f"🚀 Initial push complete. {branch} is now live.")
###        else:
###            logging.error(f"❌ Unexpected Git error: {e}")
##    # 1. Check if the local repo has ANY commits
##    try:
##        repo.head.commit
##    except (ValueError, git.exc.BadName):
##        logging.info("🌑 Local repo is empty. Staging files and creating initial commit...")
##        repo.git.add(A=True) # Stage all files
##        repo.index.commit("initial commit: system bootstrap")
##
##    # 2. Now attempt the push
##    try:
##        logging.info(f"🚀 Pushing {branch} to origin...")
##        # Using -u (set-upstream) here handles the tracking link automatically
##        repo.git.push('-u', 'origin', branch)
##        logging.info("✅ Remote established and synchronized.")
##    except git.GitCommandError as e:
##        logging.error(f"❌ Push failed: {e.stderr}")
##        raise
#def ensure_synchronized_source(remote_url, target_dir, branch="main"):
#    import git
#    from git import Repo
###    from github import Github, GithubException # NOTE was missing. probably necessary for creating the repo upstream
#
#    # 1. Check remote existence using GitPython's cmd interface
#    remote_exists = False
#    try:
#        git.cmd.Git().ls_remote(remote_url)
#        remote_exists = True
#    except git.exc.GitCommandError:
#        remote_exists = False
#
#    local_exists = (target_dir / ".git").exists()
#
#    # --- CASE 1: No Remote, No Local ---
#    if not remote_exists and not local_exists:
#        logging.info("🌑 Case 1: Creating both.")
#        repo = Repo.init(target_dir)
#        _ensure_remote_repo_exists(remote_url)
#        origin = repo.create_remote('origin', remote_url)
#
#        # Stage existing files (provisioned by your other code) and push
#        repo.git.add(A=True)
#        if repo.index.diff("HEAD"): # Only commit if files exist
#            repo.index.commit("initial bootstrap")
#        origin.push(u=branch)
#
#    # --- CASE 2: Remote exists, No Local ---
#    elif remote_exists and not local_exists:
#        logging.info("📥 Case 2: Cloning existing remote.")
#        # This handles the 'non-fast-forward' issue by adopting the remote history
#        Repo.clone_from(remote_url, target_dir)
#
#    # --- CASE 3: Local exists, No Remote ---
#    elif local_exists and not remote_exists:
#        logging.info("🛰 Case 3: Creating remote for existing local.")
#        repo = Repo(target_dir)
#        _ensure_remote_repo_exists(remote_url)
#        if 'origin' not in repo.remotes:
#            repo.create_remote('origin', remote_url)
#
#        # Ensure we have a commit to push
#        if not repo.heads:
#            repo.git.add(A=True)
#            repo.index.commit("initial bootstrap")
#        repo.remotes.origin.push(u=branch)
#
#    # --- CASE 4: Both Exist ---
#    elif local_exists and remote_exists:
#        logging.info("🔄 Case 4: Syncing.")
#        repo = Repo(target_dir)
#        origin = repo.remotes.origin
#        try:
#            origin.pull(branch)
#            origin.push(branch)
#        except git.exc.GitCommandError as e:
#            logging.error(f"❌ Discrepancy detected. Aborting.\n{e}")
#            raise SystemExit("Manual Git intervention required.")
def ensure_synchronized_source(project_root: Path) -> None:
    """The clean entry point for the Bootstrapper's Git stage."""
    import git
    #from git import Repo
    # TODO import github ????? how to create remote repo ????

    branch = os.getenv('GIT_BRANCH', 'main')

    # 1. Identity Discovery: Resolve the Remote URL
    remote_url = None
    try:
        # Check if local .git exists to extract existing remote
        if (project_root / ".git").exists():
            repo = git.Repo(project_root)
            if 'origin' in repo.remotes:
                remote_url = repo.remotes.origin.url
                logging.info(f"✔ Found existing remote: {remote_url}")
    except Exception:
        remote_url = None

    # Fallback to Env/Template if not discovered from disk
    if not remote_url:
        current_org = os.getenv('ORGANIZATION', 'InnovAnon-Inc')
        remote_url = os.getenv('GIT_REMOTE_URL',
                               f'https://github.com/{current_org}/{project_root.stem}.git')
        logging.info(f"ℹ Using discovered remote: {remote_url}")

    # 2. State Detection
    remote_exists = False
    try:
        # Ping remote without needing a local repo
        git.cmd.Git().ls_remote(remote_url)
        remote_exists = True
    except git.exc.GitCommandError:
        remote_exists = False

    local_exists = (project_root / ".git").exists()

    # 3. The Four-Way Logic Gate (No Boilerplate Content)

    # Case 1: No Remote and No Local -> Create Both
    if not remote_exists and not local_exists:
        # FIXME error in this branch
#Traceback (most recent call last):
#  File "/home/frederick/src/py/latest/ia_docker/../../ia/sad.py", line 3290, in <module>
#    main()
#    ~~~~^^
#  File "/home/frederick/src/py/latest/ia_docker/../../ia/sad.py", line 3115, in main
#    bootstrap_execution_mode(root, name)
#    ~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^
#  File "/home/frederick/src/py/latest/ia_docker/../../ia/sad.py", line 3092, in bootstrap_execution_mode
#    ensure_synchronized_source(root)
#    ~~~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^
#  File "/home/frederick/src/py/latest/ia_docker/../../ia/sad.py", line 1318, in ensure_synchronized_source
#    if repo.index.diff("HEAD") or not repo.heads:
#       ~~~~~~~~~~~~~~~^^^^^^^^
#  File "/home/frederick/venv/lib/python3.13/site-packages/git/index/base.py", line 1517, in diff
#    other = self.repo.rev_parse(other)
#  File "/home/frederick/venv/lib/python3.13/site-packages/git/repo/fun.py", line 415, in rev_parse
#    obj = name_to_object(repo, rev)
#  File "/home/frederick/venv/lib/python3.13/site-packages/git/repo/fun.py", line 202, in name_to_object
#    raise BadName(name)
#gitdb.exc.BadName: Ref 'HEAD' did not resolve to an object

        logging.info("🌑 Case 1: No remote, no local. Initializing both.")
        repo = git.Repo.init(project_root)
        _ensure_remote_repo_exists(remote_url)
        origin = repo.create_remote('origin', remote_url)

        # Stage your provisioned files (README/init/etc) and push
        repo.git.add(A=True)
        if repo.index.diff("HEAD") or not repo.heads:
            repo.index.commit("initial bootstrap")
        origin.push(u=branch)

    # Case 2: Remote exists but No Local -> Clone (Fixes non-fast-forward)
    elif remote_exists and not local_exists:
        logging.info("📥 Case 2: Remote exists, no local. Cloning.")
        git.Repo.clone_from(remote_url, project_root)
        # TODO what if our directory is non empty ? 

    # Case 3: Local exists but No Remote -> Create Remote & Push
    elif local_exists and not remote_exists:
        logging.info("🛰 Case 3: Local exists, no remote. Creating GitHub repo.")
        repo = git.Repo(project_root)
        _ensure_remote_repo_exists(remote_url)
        if 'origin' not in repo.remotes:
            repo.create_remote('origin', remote_url)

        # Ensure there is a commit to push
        if not repo.heads:
            repo.git.add(A=True)
            repo.index.commit("initial bootstrap")
        repo.remotes.origin.push(u=branch)

    # Case 4: Both Exist -> Pull/Push or Abort
    elif local_exists and remote_exists:
        logging.info("🔄 Case 4: Both exist. Synchronizing.")
        repo = git.Repo(project_root)
        origin = repo.remotes.origin
        try:
            origin.pull(branch)
            origin.push(branch)
            logging.info("✅ Synchronization successful.")
        except git.exc.GitCommandError as e:
            logging.error(f"❌ Discrepancy detected between local and remote. Aborting.\n{e}")
            raise SystemExit("Manual Git intervention required.")

##
#
##

def get_eligible_files_git(repo_path: Path, extensions: List[str]) -> List[Path]:
    """Uses GitPython to find files not ignored by git."""
    import git
    #from git import Repo
    repo = git.Repo(repo_path)
    
    eligible = []
    # Get all files tracked or potentially trackable (ignoring those in .gitignore)
    # 'ls-files' is the most efficient way to get this list
    tracked_files = repo.git.ls_files(cached=True, others=True, exclude_standard=True).splitlines()
    
    for f in tracked_files:
        path = (repo_path / f).resolve()
        if path.suffix in extensions and path.exists():
            eligible.append(path)
            
    return eligible

def mv_py_pyx(root:Path) -> None:
    logging.info("🚚 Moving .py files to .pyx...")
    # We only want to move files that are currently .py
    eligible:List[Path] = get_eligible_files_git(root, extensions=['.py'])

    entry_point:Path = Path(sys.argv[0]).resolve()

    for py_file in eligible:

        if py_file.name in ('setup.py', 'version.py', ):
            continue

        if py_file == entry_point:
            logging.debug(f"Skipping entry point: {py_file.name}")
            continue

        pyx_file:Path = py_file.with_suffix('.pyx')
        if not pyx_file.exists():
            logging.info(f"Rename: {py_file.name} -> {pyx_file.name}")
            py_file.rename(pyx_file)
        else:
            logging.warning(f"Target already exists, skipping: {pyx_file.name}")

def ln_s_pyx_py(root:Path) -> None:
    logging.info("🔗 Creating .py -> .pyx symlinks...")
    # Now we look for the .pyx files we just created
    eligible:List[Path] = get_eligible_files_git(root, extensions=['.pyx'])

    for pyx_file in eligible:
        py_link:Path = pyx_file.with_suffix('.py')

        if not py_link.exists():
            logging.info(f"Link: {py_link.name} -> {pyx_file.name}")
            # Use only the filename for the source to keep links relative
            os.symlink(pyx_file.name, py_link)
        elif not py_link.is_symlink():
            logging.warning(f"File exists and is not a link, won't overwrite: {py_link.name}")

def create_gitignore(gitignore:Path, clobber:bool=False)->bool:
    assert clobber or (not gitignore.exists())
    ignores:List[str] = [
            'build/',
            'dist/',
            'version.py',
            '__pycache__/',
            '*.cpp',
            '*.egg-info/',
            '.eggs/',
            '*.so',
            '*.o',
            '.env',
            '*~',
            '.*.swp',
            '.*.swx',
            '*.afdo',
            'hook-*.py',
            'bootstrap-*.py',
            '*.spec',
            '.models/',
    ]
    ignore :str       = '\n'.join(ignores)
    with open(gitignore, 'w') as f:
        f.write(ignore)
    assert gitignore.is_file()
   
def create_gitignore_if_not_exists(gitignore:Path, clobber:bool=False)->bool:
    if (not clobber) and gitignore.exists():
        assert gitignore.is_file()
        return False
    assert clobber or (not gitignore.exists())
    create_gitignore(gitignore, clobber=clobber)
    assert gitignore.is_file()
    return True

def create_pyproject_toml(pyproject_toml:Path, name:str, description:str, clobber:bool=False)->None:
    #import tomli
    #import tomllib
    import tomli_w
    assert clobber or (not pyproject_toml.exists())
    
    # Define the "Platonic Ideal"
    doc = {
        "build-system": {
            "requires"       : [
                #"build",
                "Cython",
                #"PyInstaller",
                "setuptools>=61.0.0",
                "setuptools-scm>=8.0",
                "wheel"
            ],
            "build-backend"  : "setuptools.build_meta"
        },
        "project"     : {
            "name"           : name,
            "dynamic"        : ["dependencies", "version"],
            "description"    : description,
            "readme"         : "README.md",
            "requires-python": ">=3.8",
            "license"        : "MIT", #{"text": "MIT"},
            "authors"        : [{"name": "InnovAnon, Inc."}], # TODO don't hard code this either ?
        },
        "tool"        : {
            "setuptools"     : { # TODO what about these ? *.so, *.o, .env, *~, .*.swp, .*.swx, *.afdo, hook-*.py, bootstrap-*.py, *.spec
                "packages": {
                    "find": {
                        "where"  : ["."],
                        "exclude": ["build*", "dist*", "tests*", "logs*", "__pycache__*", ".models*", ".*"] # TODO .gitignore-aware
                    }
                },
                #"package-data": {
                #    "": ["*.pyx", "*.pyd", "*.pxd"]
                #}
                "package-data": { # NOTE testing. probably wrong. might leak source
                    "*": ["*.pyx", "*.pyd", "*.pxd", "*.cpp", "*.h"],
                },
                "include-package-data": True,
            },
            "setuptools_scm" : {"write_to": "version.py"} # TODO write to sub module ???
        }
    }

    if pyproject_toml.exists():
        try:
            with open(pyproject_toml, "rb") as f:
                #if tomli.load(f) == doc:
                if tomllib.load(f) == doc:
                    logging.info("✅ pyproject.toml is already in the ideal state.")
                    return
        except Exception as e:
            logging.warning(f"⚠️ Existing pyproject.toml is malformed: {e}")
            raise e

    logging.info(f"📝 Synchronizing {pyproject_toml.name}...")
    with open(pyproject_toml, "wb") as f:
        tomli_w.dump(doc, f)
    assert pyproject_toml.is_file()

def create_pyproject_toml_if_not_exists(pyproject_toml:Path, name:str, description:str, clobber:bool=False)->bool:
    if (not clobber) and pyproject_toml.exists():
        assert pyproject_toml.is_file()
        return False
    assert clobber or (not pyproject_toml.exists())
    #with bootstrapped(dependencies={'tomli': 'tomli', 'tomli_w': 'tomli_w',}):
    create_pyproject_toml(pyproject_toml, name, description, clobber=clobber)
    assert pyproject_toml.is_file()
    return True

def merge_compiler_flags()->None:
    """
    Parses current and env flags into a key-value map to handle overrides 
    (e.g., -O2 -> -O3) and ensures 'Last-In-Wins' behavior.
    """
    target_keys = ['OPT', 'CFLAGS', 'PY_CFLAGS', 'PY_CORE_CFLAGS', 'CONFIGURE_CFLAGS', 'LDSHARED']
    cvars = sysconfig.get_config_vars()

    def tokenize_to_dict(flag_list):
        """Converts flags into a dict for easy overriding."""
        result = {}
        # We use a placeholder for flags that don't take arguments (like -pipe)
        for f in flag_list:
            if f.startswith('-O'): result['-O'] = f
            elif f.startswith('-march='): result['-march'] = f
            elif f.startswith('-mtune='): result['-mtune'] = f
            elif f.startswith('-g'): result['-g'] = f  # catches -g, -g0, -g3
            else: result[f] = None
        return result

    # 1. Capture Environment Intent
    env_flags = shlex.split(os.environ.get('CFLAGS', ''))
    env_overrides = tokenize_to_dict(env_flags)

    for key in target_keys:
        if key not in cvars: continue
        
        # 2. Tokenize existing Python defaults
        current_flags = shlex.split(cvars[key])
        flag_dict = tokenize_to_dict(current_flags)

        # 3. Apply Overrides (Environment values replace Python defaults)
        flag_dict.update(env_overrides)

        # 4. Reconstruct the string
        # If value is None, it's a standalone flag; otherwise, it's the full string (-O3)
        final_flags = [f if v is None else v for f, v in flag_dict.items()]
        cvars[key] = " ".join(final_flags)

def _make_dict_init()->ast.AST:
    """_kwargs = dict(kwargs)"""
    return ast.Assign(
        targets=[ast.Name(id='_kwargs', ctx=ast.Store())],
        value=ast.Call(func=ast.Name(id='dict', ctx=ast.Load()),
                       args=[ast.Name(id='kwargs', ctx=ast.Load())], keywords=[])
    )

def _make_package_logic()->ast.AST:
    """if 'packages' not in kwargs: _kwargs['packages'] = find_packages()"""
    return ast.If(
        test=ast.Compare(left=ast.Constant(value='packages'), ops=[ast.NotIn()],
                         comparators=[ast.Name(id='kwargs', ctx=ast.Load())]),
        body=[ast.Assign(
            targets=[ast.Subscript(value=ast.Name(id='_kwargs', ctx=ast.Load()), slice=ast.Constant(value='packages'))],
            value=ast.Call(func=ast.Name(id='find_packages', ctx=ast.Load()), args=[], keywords=[])
        )],
        orelse=[]
    )

def _make_cython_ext_logic()->ast.AST:
    """if 'ext_modules' not in kwargs: ... cythonize Extension('*', ['*/*.pyx'])"""
    ext_call = ast.Call(
        func=ast.Name(id='Extension', ctx=ast.Load()),
        #args=[ast.Constant(value='*'), ast.List(elts=[ast.Constant(value='*/*.pyx')])],
        args=[ast.Constant(value='*'), ast.List(elts=[ast.Constant(value='**/*.pyx')])],
        keywords=[ast.keyword(arg='language', value=ast.Constant(value='c++'))]
    )
    cythonize_call = ast.Call(
        func=ast.Name(id='cythonize', ctx=ast.Load()),
        args=[ast.List(elts=[ext_call])],
        keywords=[ast.keyword(arg='compiler_directives',
                             value=ast.Dict(keys=[ast.Constant(value='language_level')],
                                            values=[ast.Constant(value='3')])),

                  ast.keyword(arg='build_dir', value=ast.Constant(value='build')), ]
    )
    return ast.If(
        test=ast.Compare(left=ast.Constant(value='ext_modules'), ops=[ast.NotIn()],
                         comparators=[ast.Name(id='kwargs', ctx=ast.Load())]),
        body=[ast.Assign(
            targets=[ast.Subscript(value=ast.Name(id='_kwargs', ctx=ast.Load()), slice=ast.Constant(value='ext_modules'))],
            value=cythonize_call
        )],
        orelse=[]
    )

#def _make_data_exclusion_logic()->ast.AST:
#    """Excludes source files from the final wheel/package."""
#    exclusions = ast.Dict(
#        keys=[ast.Constant(value='')],
#        values=[ast.List(elts=[ast.Constant(value=v) for v in [ # TODO .gitignore-aware
#            #'*.cpp', '*.pyx', '*.py',
#            'hook-*.py', 'main-*.py', '__pycache__', '.env'
#        ]])]
#    )
#    return ast.If(
#        test=ast.Compare(left=ast.Constant(value='exclude_package_data'), ops=[ast.NotIn()],
#                         comparators=[ast.Name(id='kwargs', ctx=ast.Load())]),
#        body=[ast.Assign(
#            targets=[ast.Subscript(value=ast.Name(id='_kwargs', ctx=ast.Load()), slice=ast.Constant(value='exclude_package_data'))],
#            value=exclusions
#        )],
#        orelse=[]
#    )
def _make_data_exclusion_logic() -> ast.AST:
    """Excludes source files from the final wheel/package while allowing build."""
    exclusions = ast.Dict(
        keys=[ast.Constant(value='')],
        values=[ast.List(elts=[ast.Constant(value=v) for v in [
            # The Protection List:
            '*.cpp',    # Intermediate C++ files
            '*.pyx',    # Cython source
            '*.py',     # Original Python source (now compiled to .so/.pyd)
            '*.pxd',    # Cython headers
            '*.h',      # C headers
            '*.afdo',
            'hook-*.py',
            #'main-*.py',
            'bootstrap-*.py',
            '*.spec',
            '__pycache__',
            '.env'

            # TODO what about these ?
            #'build/',
            #'dist/',
            #'*.egg-info/',
            #'.eggs/',
            #'*.so',
            #'*.o',
            #'*~',
            #'.*.swp',
            #'.*.swx',
            #'*.afdo',
            #'.models/',
        ]])]
    )
    return ast.If(
        test=ast.Compare(
            left=ast.Constant(value='exclude_package_data'),
            ops=[ast.NotIn()],
            comparators=[ast.Name(id='kwargs', ctx=ast.Load())]
        ),
        body=[ast.Assign(
            targets=[ast.Subscript(
                value=ast.Name(id='_kwargs', ctx=ast.Load()),
                slice=ast.Constant(value='exclude_package_data')
            )],
            value=exclusions
        )],
        orelse=[]
    )

def _get_compiler_logic_ast()->ast.AST:
    source:str = inspect.getsource(merge_compiler_flags)
    return ast.parse(source)

def _generate_merged_setup_ast()->ast.AST:
    # 1. Boilerplate imports and comments
    header = ast.parse(
        "#! /usr/bin/env python3\n"
        "# cython: language_level=3\n"
        "# distutils: language=c++\n"
    ).body
    
    imports = ast.parse(
        "import sysconfig, shlex, os\n"
        "from setuptools import find_packages, Extension, setup as _setup\n"
        "from Cython.Build import cythonize\n"
    ).body

    # 2. Re-insert the compiler flag merging logic (from previous step)
    compiler_logic = _get_compiler_logic_ast()

    # 3. The setup wrapper body
    setup_body = [
        ast.Expr(value=ast.Call(func=ast.Name(id='merge_compiler_flags', ctx=ast.Load()), args=[], keywords=[])),
        _make_dict_init(),
        _make_package_logic(),
        _make_cython_ext_logic(),
        _make_data_exclusion_logic(),
        # _setup(*args, **_kwargs)
        ast.Expr(value=ast.Call(
            func=ast.Name(id='_setup', ctx=ast.Load()),
            args=[ast.Starred(value=ast.Name(id='args', ctx=ast.Load()), ctx=ast.Load())],
            keywords=[ast.keyword(arg=None, value=ast.Name(id='_kwargs', ctx=ast.Load()))]
        ))
    ]

    setup_func = ast.FunctionDef(
        name='setup',
        args=ast.arguments(posonlyargs=[], args=[], vararg=ast.arg(arg='args'),
                           kwonlyargs=[], kw_defaults=[], kwarg=ast.arg(arg='kwargs'), defaults=[]),
        body=setup_body,
        decorator_list=[],
        returns=ast.Name(id='None', ctx=ast.Load())
    )

    # 4. Main Guard
    main_guard = ast.parse(
        "if __name__ == '__main__':\n"
        "    setup(use_scm_version=True, setup_requires=['setuptools_scm'])\n"
    ).body

    return ast.Module(body=header + imports + [compiler_logic, setup_func] + main_guard, type_ignores=[])

def create_setup_py(setup_py:Path, clobber:bool=False)->bool:
    """ fully and accurately implements all 6 features known to be required """
    assert clobber or (not setup_py.exists())
    # feature 1: ext_modules
    #if('ext_modules' not in kwargs):
    #	#pyx_glob    :str                = str(f'{project_name}/*.pyx')
    #	pyx_glob    :str                = '*/*.pyx'
    #	extension_glob                  = Extension(
    #		'*',
    #		sources  =[ pyx_glob,],
    #        		language = "c++",)
    #	extensions  :List[Extension]    = [ extension_glob,]
    #	_kwargs['ext_modules']          = cythonize(
    #		extensions,
    #		compiler_directives={
    #			'language_level':  '3',
    #			#'embedsignature': True, # PyInstaller
    #		},)
    # feature 2: packages
	#if('packages'             not in kwargs):
	#	_kwargs['packages']                      = find_packages()
    # feature 3: package_data
    #if('package_data'         not in kwargs):
    #	_kwargs['package_data']         = {
    #        		'': ['*.so',],
    #    	}
    # feature 4: exclude_package_data
    #if('exclude_package_data' not in kwargs):
    #	_kwargs['exclude_package_data']          = {
    #        		'': ['*.cpp', '*.pyx', '*.py', 'hook-*.py', 'main-*.py', '__pycache__', '.env',] # '*.py', # TODO .gitignore-aware
    #    	}
    # feature 5: zip_safe
    #if('zip_safe'             not in kwargs): # PyInstaller
    #	_kwargs['zip_safe']             = False
    # feature 6: include_package_data
    #if('include_package_data' not in kwargs): # PyInstaller
    #	_kwargs['include_package_data'] = True

    setup_ast:ast.AST = _generate_merged_setup_ast()
    ast.fix_missing_locations(setup_ast)
    setup_src:str     = ast.unparse(setup_ast)
    with open(setup_py, 'w') as f:
        f.write(setup_src) 
    assert setup_py.is_file()

def create_setup_py_if_not_exists(setup_py:Path, clobber:bool=False)->bool:
    if (not clobber) and setup_py.exists():
        assert setup_py.is_file()
        return False
    assert clobber or (not setup_py.exists())
    create_setup_py(setup_py, clobber=clobber)
    assert setup_py.is_file()
    return True

def nonempty_lines(out:str)->List[str]:
    res :List[str] = out.split('\n')
    return list(filter(None,res))

def create_requirements_txt(requirements_txt:Path, root:Path, clobber:bool=False)->None:
    import pipreqs.pipreqs
    assert clobber or (not requirements_txt.exists())
    #args:List[str] = ['pipreqs', '--print', '--mode', 'no-pin', ] # --proxy
    #req :str       = subprocess.check_call(args, universal_newlines=True, )
    #reqs:List[str] = nonempty_lines(req)
    reqs:List[str] = pipreqs.pipreqs.get_all_imports(root)
    req :str       = '\n'.join(reqs)
    with open(requirements_txt, 'w') as f:
        f.write(req)
    assert requirements_txt.is_file()

def create_requirements_txt_if_not_exists(requirements_txt:Path, root:Path, clobber:bool=False)->None:
    if (not clobber) and requirements_txt.exists():
        assert requirements_txt.is_file()
        return False
    assert clobber or (not requirements_txt.exists())
    #with bootstrapped(dependencies={ 'pipreqs': 'pipreqs',}):
    create_requirements_txt(requirements_txt, root, clobber=clobber)
    assert requirements_txt.is_file()
    return True

def create_readme_md(readme_md:Path, name:str, description:str, clobber:bool=False)->None:
    #import mdutils
    import mdutils.mdutils
    from mdutils.mdutils import MdUtils # TODO double check that bootstrapped() handles this
    assert clobber or (not readme_md.exists())
    # TODO the boilerplate markdown could look a little better
    mdFile = MdUtils(file_name=str(readme_md), title=name)
    mdFile.new_header(level=1, title='Overview')  # style is set 'atx' format by default.
    mdFile.new_paragraph(description)
    # NOTE we can't do this well without being dockerized
    # TODO AI if dockerized
    mdFile.new_table_of_contents(table_title='Contents', depth=2)
    mdFile.create_md_file()
    assert readme_md.is_file()

def create_readme_md_if_not_exists(readme_md:Path, name:str, description:str, clobber:bool=False)->None:
    if (not clobber) and readme_md.exists():
        assert readme_md.is_file()
        return False
    assert clobber or (not readme_md.exists())
    #with bootstrapped(dependencies={'mdutils' : 'MdUtils',}):
    create_readme_md(readme_md, name, description, clobber=clobber)
    assert readme_md.is_file()
    return True

#def is_ignored(path: Path, repo) -> bool:
#    """Checks if a path is ignored by git using the active repository's rules."""
#    try:
#        # returns a list of ignored files; if empty, path is not ignored
#        return len(repo.ignored(path)) > 0
#    except Exception as e:
#        logging.error(e)
#        # Fallback for special dirs
#        return path.name == ".git" or "pycache" in path.name # TODO the error is safe to ignore ?
def is_ignored(path: Path, repo) -> bool:
    # Hard-exclude the metadata dir regardless of what .gitignore says
    if path.name == ".git" or ".git/" in path.as_posix():
        return True
    try:
        return len(repo.ignored(path)) > 0
    except Exception:
        return False

def get_python_files_in_dir(directory: Path) -> List[str]:
    """Returns stem names of all .py and .pyx files, excluding __init__."""
    results:List[str] = [
        f.stem
        for f in directory.iterdir()
        if f.is_file()
        and f.suffix in ('.py', '.pyx')
        and f.stem not in ('__init__', '__main__', 'setup')
    ]
    return list(set(results))

def generate_init_content(module_names: List[str]) -> str:
    """
    Creates 'from .module import *' for each module using AST
    to ensure clean, valid syntax.
    """
    if not module_names:
        return "# Package marker\n"

    nodes = []
    for name in module_names:
        # Represents: from .<name> import *
        node = ast.ImportFrom(
            module=name,
            names=[ast.alias(name='*', asname=None)],
            level=1
        )
        nodes.append(node)

    result:ast.AST = ast.Module(body=nodes, type_ignores=[])
    ast.fix_missing_locations(result)
    return ast.unparse(result)

def create_init_py_if_not_exists(root: Path, clobber:bool=False) -> bool: # TODO skip top level ?
    """
    Recursively ensures __init__.py exists in all non-ignored directories
    and populates them with wildcard imports of sibling modules.

    as the name implies, it never clobbers pre-existing __init__.py files
    """
    import git
    #from git import Repo, InvalidGitRepositoryError

    #try:
    repo = git.Repo(root, search_parent_directories=True)
    #except InvalidGitRepositoryError:
    #    logging.warning("⚠️ No git repo found; ignore-checking may be inaccurate.")
    #    repo = None

    modified = False

    # walk(top_down=True) allows us to skip ignored subdirectories entirely
    for current_dir, dirs, files in root.walk():
        # 1. Filter out ignored directories so we don't descend into them
        #if repo:
        dirs[:] = [d for d in dirs if not is_ignored(Path(current_dir) / d, repo)]

        if Path(current_dir).resolve() == root.resolve():
            continue

        target_init = Path(current_dir) / "__init__.py"

        # 2. Skip if already exists (or logic could be added to clobber/update)
        if (not clobber) and target_init.exists():
            continue

        # 3. Identify modules to import
        modules = get_python_files_in_dir(Path(current_dir))

        # 4. Generate and write
        #try:
        content = generate_init_content(modules)
        with open(target_init, "w") as f:
            #f.write(f'""" Auto-generated by Bootstrapper """\n\n')
            f.write(content)

        logging.info(f"✨ Created {target_init}")
        modified = True
        #except Exception as e:
        #    logging.error(f"❌ Failed to create {target_init}: {e}")
        #    raise e

    return modified

def find_entrypoint_in_file(py_file: Path):
    """Returns (function_name, is_async) if a 'main' function exists."""
    try:
        tree = ast.parse(py_file.read_text())
        for node in tree.body:
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == 'main':
                return node.name, isinstance(node, ast.AsyncFunctionDef)
    except Exception:
        pass
    return None, False

def generate_main_content(entry_module: str, is_async: bool) -> str:
    """Constructs the __main__.py bridge using AST."""
    nodes = []

    # 1. from .<entry_module> import main
    nodes.append(ast.ImportFrom(
        module=entry_module,
        names=[ast.alias(name='main', asname=None)],
        level=1
    ))

    # 2. if is_async: import asyncio
    if is_async:
        nodes.append(ast.Import(names=[ast.alias(name='asyncio', asname=None)]))

    # 3. Create the call: main() or asyncio.run(main())
    main_call = ast.Call(
        func=ast.Name(id='main', ctx=ast.Load()),
        args=[],
        keywords=[]
    )

    if is_async:
        main_call = ast.Call(
            func=ast.Attribute(
                value=ast.Name(id='asyncio', ctx=ast.Load()),
                attr='run',
                ctx=ast.Load()
            ),
            args=[main_call],
            keywords=[]
        )

    # 4. Construct: if __name__ == '__main__': ...
    if_main = ast.If(
        test=ast.Compare(
            left=ast.Name(id='__name__', ctx=ast.Load()),
            ops=[ast.Eq()],
            comparators=[ast.Constant(value='__main__')]
        ),
        body=[ast.Expr(value=main_call)],
        orelse=[]
    )
    nodes.append(if_main)

    result:ast.AST = ast.Module(body=nodes, type_ignores=[])
    ast.fix_missing_locations(result)
    return ast.unparse(result)

def create_main_py_if_not_exists(root: Path, clobber:bool=False) -> bool: # TODO skip top level ?
    """ never clobbers pre-existing __main__.py files """
    #from git import Repo
    import git
    repo = git.Repo(root, search_parent_directories=True)
    modified = False

    for current_dir, dirs, files in root.walk():
        # Filter directories
        #dirs[:] = [d for d in dirs if d not in ('.git', '__pycache__') and not is_ignored(Path(current_dir) / d, repo)]
        dirs[:] = [d for d in dirs if not is_ignored(Path(current_dir) / d, repo)]

        if Path(current_dir).resolve() == root.resolve():
            continue

        target_main = Path(current_dir) / "__main__.py"
        if (not clobber) and target_main.exists():
            continue

        modules = get_python_files_in_dir(Path(current_dir))
        entry_module = None
        is_async = False

        for mod in modules: # TODO find all entrypoints and make a decision
            func, found_async = find_entrypoint_in_file(Path(current_dir) / f"{mod}.py")
            if func:
                entry_module, is_async = mod, found_async
                break

        if entry_module:
            content = generate_main_content(entry_module, is_async)
            with open(target_main, "w") as f:
                #f.write(f'""" Auto-generated entrypoint bridge """\n\n')
                f.write(content)
                #f.write("\n") # Ensure trailing newline

            logging.info(f"🚀 Created entrypoint bridge: {target_main}")
            modified = True

    return modified

def python_m_build(build_env:Dict[str,str])->None:
    subprocess.check_call([sys.executable, "-m", "build",], env=build_env)

def install_wheels(dist_dir:Path)->None:
    wheels = list(dist_dir.glob('*.whl'))
    if not wheels:
        raise FileNotFoundError("No wheels found in dist/ to install.")
    # Sort by mtime to get the latest build
    latest_wheel = max(wheels, key=lambda p: p.stat().st_mtime)
    logging.info(f"📦 Installing {latest_wheel}...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--force-reinstall", str(latest_wheel)],)

def create_module_dir_if_not_exists(root: Path, module_dir: Path) -> bool:
    """
    Creates a package directory if the project is currently 'flat'.
    If non-ignored directories already exist, we assume a structure is in place.
    """
    #from git import Repo, InvalidGitRepositoryError
    import git
    
    try:
        repo = git.Repo(root, search_parent_directories=True)
    except git.InvalidGitRepositoryError:
        repo = None

    # Check for existing directories that aren't metadata/ignored
    existing_subdirs = []
    for d in root.iterdir():
        if d.is_dir():
            # Skip metadata and hidden dirs
            #if d.name in ('.git', '__pycache__', '.venv', 'venv', 'dist', 'build'):
            #    continue
            # Check if git ignores it
            if repo and is_ignored(d, repo):
                continue
            existing_subdirs.append(d)

    if not existing_subdirs:
        logging.info(f"📁 Flat project detected. Creating module directory: {module_dir}")
        module_dir.mkdir(parents=True, exist_ok=True)
        return True
    
    logging.info("ℹ️ Project already has subdirectories; skipping module_dir creation.")
    return False

def create_manifest_in(manifest_in: Path, clobber:bool=False) -> None:
    """
    Creates a MANIFEST.in to ensure all source/header files are included in the
    Source Distribution (sdist), which is required for successful isolated builds.
    """
    assert clobber or (not manifest_in.exists())

    # We use recursive-include to ensure that no matter how many sub-modules
    # exist, their Cython and C++ source files are bundled.
    lines = [
        "# Auto-generated by Bootstrapper - do not edit manually",
        "include README.md",
        "include requirements.txt",
        "include pyproject.toml",
        "include setup.py",
        "include version.py", # TODO gotta be in submodule
        "",
        "# Include all Cython/C++ source across the entire tree",
        "global-include *.pyx",
        "global-include *.pxd",
        "global-include *.cpp",
        "global-include *.h",
        "global-include *.hpp",
        "",
        "# Exclude build artifacts and metadata",
        "global-exclude *.py[cod]",
        "global-exclude __pycache__",
        "global-exclude .models",
        "global-exclude .git*",
        "global-exclude .env",
        "prune build",
        "prune dist",
    ]

    content = "\n".join(lines).strip() + "\n"

    # Check if we actually need to write to avoid unnecessary disk churn
    #if manifest_in.exists() and manifest_in.read_text() == content:
    #    return False

    logging.info(f"📜 Synchronizing {manifest_in.name} (Source Manifest)")
    manifest_in.write_text(content)
    #return True

def create_manifest_in_if_not_exists(manifest_in:Path, clobber:bool=False)->bool:
    if (not clobber) and manifest_in.exists():
        assert manifest_in.is_file()
        return False
    assert clobber or (not manifest_in.exists())
    #with bootstrapped(dependencies={'mdutils' : 'MdUtils',}):
    create_manifest_in(manifest_in, clobber=clobber)
    assert manifest_in.is_file()
    return True

def reexec_as_compiled() -> None:
    venv_executable = Path(sys.executable)
    argv            = get_new_argv(venv_executable)

    # Surgical swap: find the script and turn it into -m
    # We only do this HERE to avoid breaking your other re-exec flows
    #logging.warn('\n\n\n')
    flag:bool = False
    for i, arg in enumerate(argv):
    #    logging.warn(f'argv[{i}] = {arg}')
        p = Path(arg)
        if p.suffix in ['.py', '.pyx'] and p.exists():
            package_name = p.stem
            # Replace script.py with -m package
            argv[i:i+1] = ["-m", package_name]
            flag = True
            break
    #if not flag:
    #    logging.warn()
    #    return
    assert flag
    #logging.warn('\n\n\n')

    logging.info(f"♻️ Pivoting to compiled module: {argv}")
    os.execv(venv_executable, argv)

def detect_compiler_type() -> str:
    """
    Detects if the active compiler is 'clang' or 'gcc'.
    Checks env vars first, then sysconfig, then binary help strings.
    """
    # 1. Check environment variables (the standard override)
    cxx = os.environ.get('CXX') or os.environ.get('CC')

    # 2. Fallback to sysconfig (what Python was built with / defaults to)
    if not cxx:
        cxx = sysconfig.get_config_var('CXX') or sysconfig.get_config_var('CC')

    # 3. Default to 'g++' if still nothing
    if not cxx:
        cxx = 'g++'

    # Clean the path (e.g., 'ccache g++' -> 'g++')
    executable = shlex.split(cxx)[0]

    # If the executable isn't in path, we're likely going to fail anyway,
    # but let's assume gcc-like behavior
    if not shutil.which(executable):
        return 'gcc'

    #try:
    if True: # fail fast
        # Ask the compiler who it is.
        # Clang and GCC both support --version, but Clang identifies itself clearly.
        result = subprocess.run([executable, '--version'],
                                capture_output=True, text=True, check=False)
        output = result.stdout.lower() + result.stderr.lower()

        if 'clang' in output or 'apple llvm' in output:
            return 'clang'
        if 'gcc' in output or 'g++' in output:
            return 'gcc'
    #except Exception as e:
    #    pass

    return 'gcc' # Default fallback

def get_cflags(afdo_path:Path, instrumentation:bool=True, compiler_type:str|None=None)->List[str]:
    afdo_path                                = afdo_path.resolve() # just in case
    compiler_type       :str                 = compiler_type or detect_compiler_type()
    instrumentation_args:Dict[str,List[str]] = {
            'clang': ['-gmlt', '-fdebug-info-for-profiling', ],
            'gcc'  : ['-g1',   '-fno-eliminate-unused-debug-types', ],
    }
    instrumentated_args :Dict[str,List[str]] = {
            'clang': [f'-fprofile-sample-use={afdo_path}', ], # '-Wno-missing-profile'
            'gcc'  : [f'-fauto-profile={afdo_path}', ],
    }
    args                :List[str]           = []
    if instrumentation:
        _args           :List[str]           = instrumentation_args[compiler_type]
        args.extend(_args)
    
    if afdo_path.exists():
        logging.info(f'found profile: {afdo_path}')
        assert afdo_path.is_file()
        _args           :List[str]           = instrumentated_args[compiler_type]
        args.extend(_args)
        return args
    assert not afdo_path.exists()
    logging.warn(f'no profile: {afdo_path}')
    return args

def get_build_env(afdo_path: Path) -> Dict[str, str]:
    """
    Merges AFDO flags into existing CFLAGS/CXXFLAGS using shlex to ensure
    proper quoting and to avoid redundant flag spam.
    """
    # 1. Get our desired flags as a list
    new_flags_list         :List[str]     = get_cflags(afdo_path)

    env                    :Dict[str,str] = os.environ.copy()

    for key in ["CFLAGS", "CXXFLAGS"]:
        # 2. Parse existing flags into a list
        existing_val       :str           = env.get(key, "")
        existing_flags_list:List[str]     = shlex.split(existing_val)

        # 3. Merge lists.
        # Using a dict or set logic here ensures 'idempotency' of the flags themselves.
        # We put new_flags_list last so they take precedence if there's a conflict.
        merged_list        :List[str]     = existing_flags_list + [
                f
                for f in new_flags_list
                if f not in existing_flags_list]

        # 4. Join back into a shell-safe string
        env[key]                          = shlex.join(merged_list)

    return env

def transition_to_compiled(root:Path, name:str, clobber:bool=False)->None:#|None=None)->None: # TODO needs to return the wheel(s)
    assert not get_execution_mode().is_compiled
    #root            :Path          = root or Path(os.getcwd()).resolve()
    pyproject_toml  :Path          = root / 'pyproject.toml'
    setup_py        :Path          = root / 'setup.py'
    requirements_txt:Path          = root / 'requirements.txt'
    readme_md       :Path          = root / 'README.md'
    dist_dir        :Path          = root / 'dist'
    manifest_in     :Path          = root / "MANIFEST.in"
    afdo_path       :Path          = root / f'{name}.afdo'
    module_dir      :Path          = root / name
    description     :str           = 'TODO description'
    build_env       :Dict[str,str] = get_build_env(afdo_path)
    create_module_dir_if_not_exists      (root, module_dir) # clobber=clobber
    create_init_py_if_not_exists         (root,                              clobber=clobber)
    create_main_py_if_not_exists         (root,                              clobber=clobber) # TODO we need to get all __main__.py that we find/create
    mv_py_pyx                            (root) # clobber=clobber
    ln_s_pyx_py                          (root) # clobber=clobber
    #with bootstrapped(dependencies={'tomli': 'tomli', 'tomli_w': 'tomli_w',}):
    create_pyproject_toml_if_not_exists  (pyproject_toml, name, description, clobber=clobber)
    create_setup_py_if_not_exists        (setup_py,                          clobber=clobber)
    #with bootstrapped(dependencies={ 'pipreqs': 'pipreqs',}):
    create_requirements_txt_if_not_exists(requirements_txt, root,            clobber=clobber)
    #with bootstrapped(dependencies={'mdutils' : 'MdUtils',}):
    create_readme_md_if_not_exists       (readme_md,      name, description, clobber=clobber)
    create_manifest_in_if_not_exists     (manifest_in,                       clobber=clobber)
    # TODO need to determine which build we're on, i.e., for autofdo, so we set the right cflags
    with bootstrapped(dependencies={ 'build': 'build', }):
        python_m_build(build_env)
    install_wheels(dist_dir)
    # TODO only if compilng self. otherwise... gotta manage restarting external projects/processes
    #reexec_as_compiled()
    # TODO needs to return the wheel(s)

#def transition_to_deb(root: Path, name: str, version: str = "0.1.0") -> None:
#    """
#    Creates the debian/ directory structure and builds a .deb package.
#    """
#    debian_dir = root / 'debian'
#    debian_dir.mkdir(exist_ok=True)
#
#    # 1. Control File (The heart of the package)
#    # This is where you map Python requirements to System requirements
#    create_deb_control(debian_dir, name, version)
#
#    # 2. Rules File (Tells debhelper how to build Python)
#    create_deb_rules(debian_dir)
#
#    # 3. Changelog (Debian requires this to set the version)
#    create_deb_changelog(debian_dir, name, version)
#
#    # 4. Build it
#    with bootstrapped(dependencies={'stdeb': 'stdeb'}):
#        # stdeb is the easiest way to bridge setup.py to debian/
#        subprocess.run(["python3", "setup.py", "--command-packages=stdeb.command", "bdist_deb"], cwd=root)
def transition_to_deb(root: Path, wheel_path: Path, name: str):
    """
    Wraps the existing wheel into a .deb.
    Uses the current sys.executable to ensure chroot/venv integrity.
    """
    dist_dir        :Path          = root / 'dist'
    with bootstrapped(dependencies={'wheel2deb': 'wheel2deb'}):
        subprocess.run([
            sys.executable, "-m", "wheel2deb",
            "--wheel", str(wheel_path),
            "--output-dir", str(dist_dir),
        ], check=True)

def create_hook_py(hook_py:Path, name: str, clobber:bool=False) -> None:
    """Creates a PyInstaller hook using AST to ensure compiled binaries are bundled."""
    assert clobber or (not hook_py.exists())
    
    # Utility to create: var_name = collect_func(name)
    def make_collect_assign(var_name: str, func_name: str, arg_val: str):
        return ast.Assign(
            targets=[ast.Name(id=var_name, ctx=ast.Store())],
            value=ast.Call(
                func=ast.Name(id=func_name, ctx=ast.Load()),
                args=[ast.Constant(value=arg_val)],
                keywords=[]
            )
        )

    # Building the module body
    body = [
        # from PyInstaller.utils.hooks import collect_submodules, collect_data_files, collect_dynamic_libs
        ast.ImportFrom(
            module='PyInstaller.utils.hooks',
            names=[
#                ast.alias(name='collect_submodules'),
#                ast.alias(name='collect_data_files'),
#                ast.alias(name='collect_dynamic_libs'),
                ast.alias(name='collect_all'),
            ],
            level=0
        ),
#        # hiddenimports = collect_submodules('name')
#        make_collect_assign('hiddenimports', 'collect_submodules', name),
#        # datas = collect_data_files('name')
#        make_collect_assign('datas', 'collect_data_files', name),
#        # binaries = collect_dynamic_libs('name')
#        make_collect_assign('binaries', 'collect_dynamic_libs', name)

        # TODO
        #hiddenimports = [
        #    'mypy_extensions',
        #    'tomli',
        #    'tomllib'
        #]

        ast.Assign(
            targets=[ast.Tuple(
                elts=[ast.Name(id='datas', ctx=ast.Store()), 
                      ast.Name(id='binaries', ctx=ast.Store()), 
                      ast.Name(id='hiddenimports', ctx=ast.Store())],
                ctx=ast.Store()
            )],
            value=ast.Call(
                func=ast.Name(id='collect_all', ctx=ast.Load()),
                args=[ast.Constant(value=name)],
                keywords=[]
            ),
        ),
    ]

    tree = ast.Module(body=body, type_ignores=[])
    ast.fix_missing_locations(tree)
    
    # Write the unparsed AST to the file
    hook_py.write_text(ast.unparse(tree))
    logging.info(f"🪝 Created PyInstaller hook via AST: {hook_py.name}")
    assert hook_py.is_file()

def create_hook_py_if_not_exists(hook_py:Path, name:str, clobber:bool=False)->None:
    if (not clobber) and hook_py.exists():
        assert hook_py.is_file()
        return False
    assert clobber or (not hook_py.exists())
    create_hook_py(hook_py, name, clobber=clobber)
    assert hook_py.is_file()
    return True

def create_bootstrap_py(bootstrap_py: Path, module_path: str, clobber:bool=False) -> None:
    """Generates a bootstrap that imports a specific module path and calls main()."""
    assert clobber or (not bootstrap_py.exists())
    # from {module_path} import main; main()
    tree = ast.Module(body=[
        ast.ImportFrom(module=module_path, names=[ast.alias(name='main')], level=0),
        ast.Expr(value=ast.Call(func=ast.Name(id='main', ctx=ast.Load()), args=[], keywords=[]))
    ], type_ignores=[])
    ast.fix_missing_locations(tree)
    bootstrap_py.write_text(ast.unparse(tree))
    assert bootstrap_py.is_file()

def create_bootstrap_py_if_not_exists(bootstrap_py:Path, name:str, clobber:bool=False)->None:
    if (not clobber) and bootstrap_py.exists():
        assert bootstrap_py.is_file()
        return False
    assert clobber or (not bootstrap_py.exists())
    create_bootstrap_py(bootstrap_py, name, clobber=clobber)
    assert bootstrap_py.is_file()
    return True

def run_pyinstaller(bootstrap_py: Path, bundle_name: str, root: Path) -> None:
    """Invokes PyInstaller to freeze the bootstrap script into a standalone binary."""
    import PyInstaller.__main__

    # Define paths relative to the project root
    dist_path = root / "dist"
    build_path = root / "build" / "pyinstaller" / bundle_name

    args = [
        '--onefile',
        '--name', bundle_name,
        '--additional-hooks-dir', str(root),  # Where hook-{name}.py lives
        '--distpath', str(dist_path),
        '--workpath', str(build_path),
        '--specpath', str(root),
        '--clean',
        '--noconfirm',
        # TODO prefer already-compiled artifacts: extra paths = venv site packages
        str(bootstrap_py)
    ]

    logging.info(f"📦 Bundling {bundle_name} into standalone executable...")
    
    # Using your bootstrap context manager for PyInstaller dependency
    #with bootstrapped(dependencies={'pyinstaller': 'pyinstaller'}):
    if True:
        # PyInstaller run returns None but can raise SystemExit
        try:
            PyInstaller.__main__.run(args)
        except SystemExit as e:
            if e.code != 0:
                logging.error(f"❌ PyInstaller failed for {bundle_name} with code {e.code}")
                raise

    logging.info(f"🚀 Bundling complete: {dist_path / bundle_name}")

def transition_to_bundled(root: Path, name: str, clobber: bool = False) -> None:
    """
    Finds every __main__.py in the project (excluding root)
    and bundles them into individual executables.
    """
    assert not get_execution_mode().is_bundled
    #from git import Repo
    import git
    repo = git.Repo(root, search_parent_directories=True)

    # 1. Ensure the PyInstaller hook exists for the core package
    hook_py = root / f'hook-{name}.py'
    create_hook_py_if_not_exists(hook_py, name, clobber=clobber)

    # 2. Scan for entrypoints
    for current_dir, dirs, files in root.walk():
        dirs[:] = [d for d in dirs if not is_ignored(Path(current_dir) / d, repo)]

        if Path(current_dir).resolve() == root.resolve():
            continue

        if "__main__.py" in files:
            target_main_path = Path(current_dir) / "__main__.py"
            relative_path = target_main_path.relative_to(root).parent
            bundle_name = "-".join(relative_path.parts)

            bootstrap_py = root / f"bootstrap-{bundle_name}.py"
            module_import_path = ".".join(relative_path.parts) + ".__main__"

            logging.info(f"🔎 Found entrypoint: {module_import_path}")

            # 3. Create bootstrap and run
            create_bootstrap_py_if_not_exists(bootstrap_py, module_import_path, clobber=clobber)
            #with bootstrapped({'PyInstaller': 'PyInstaller', }):
            run_pyinstaller(bootstrap_py, bundle_name, root)

#def transition_to_installed()->None:
#    assert not get_execution_mode().is_installed
#    #install_wheels(dist_dir)
#    raise NotImplementedError()

# TODO need to periodically recompile with autofdo

##
#
##

#@dataclass(frozen=True)
#class EnvState:
#    is_root     :bool
#    is_venv     :bool
#    is_docker   :bool
#    is_chroot   :bool
#    mode        :ExecutionMode
#
#    @classmethod
#    def current(cls):
#        return cls(
#            is_root     =is_root(),
#            is_venv     =is_venv(),
#            is_docker   =is_docker(),
#            is_chroot   =ischroot(),
#            mode        =get_execution_mode(),
#        )
#
#    def diff(self, other: 'EnvState') -> List[str]:
#        changes = []
#        if self.is_root != other.is_root:     changes.append(f"root({self.is_root}->{other.is_root})")
#        if self.is_venv != other.is_venv:     changes.append(f"venv({self.is_venv}->{other.is_venv})")
#        if self.is_docker != other.is_docker: changes.append(f"docker({self.is_docker}->{other.is_docker})")
#        if self.mode != other.mode:           changes.append(f"mode({self.mode}->{other.mode})")
#        return changes
#
#class Bootstrapper:
#    def __init__(self, target: EnvState)->None:
#        self.target      :EnvState = target
#
#    def reach_target(self)->None:
#        current:EnvState = EnvState.current()
#        
#        # 1. Critical Path: Virtual Environment
#        # We almost always want this first to keep the host clean.
#        if self.target.is_venv and not current.is_venv and not current.is_docker:
#            ensure_venv() # Performs re-exec
#            
#        # 2. Critical Path: Root Privileges
#        if self.target.is_root and not current.is_root:
#            elevate_if_necessary() # Performs re-exec
#            
#        # 3. Critical Path: Dockerization
#        if self.target.is_docker and not current.is_docker:
#            # We assume system deps like docker-cli are handled inside dockerize_if_necessary
#            dockerize_if_necessary() # Performs re-exec
#
#        with bootstrapped({'git': 'GitPython', 'github': 'PyGithub'}):
#            root          :Path = Path(os.getcwd()).resolve()
#            git_ignore    :Path = root / '.gitignore'
#            create_gitignore_if_not_exists(git_ignore)
#            #create_gitignore(git_ignore)
#            ensure_synchronized_source(root)
#
#            if self.target.mode.is_compiled and current.mode.is_raw:
#                transition_to_compiled(root) # will perform re-exec
#        if self.target.mode.is_bundled and ...:
#            transition_to_bundled() # will perform re-exec
#        if self.target.mode.is_installed and ...:
#            transition_to_installed() # will perform re-exec
#
#        logging.info("🎯 Target state reached: %s", current)

#def get_provision_model_env()->Dict[str,str]:
#    env_vars = os.environ.copy()
#    if platform.system() != "Linux":
#        return env_vars
#    try:
#        subprocess.check_output(['nvidia-smi'])
#        logging.info("🏎️ CUDA detected. Setting CMAKE_ARGS for GPU acceleration.")
#        env_vars["CMAKE_ARGS"] = "-DGGML_CUDA=ON"
#    except (FileNotFoundError, subprocess.CalledProcessError):
#        logging.info("💻 No GPU detected. Falling back to CPU (OpenBLAS/AVX).")
#        env_vars["CMAKE_ARGS"] = "-DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS"
#    return env_vars

def bootstrap_my_execution_mode()->None:
    raise NotImplementedError()

def bootstrap_other_execution_mode()->None:
    raise NotImplementedError()

def bootstrap_execution_mode(root:Path, name:str)->None:
    # TODO determine whether target is self or other
    #if target is self:
    #   bootstrap_my_execution_mode()
    #else:
    #   bootstrap_other_execution_mode()

    # TODO if self is target (i.e., cwd is parent of path exec'd script ?)
    mode                    :ExecutionMode = get_execution_mode()
    if not mode.is_compiled:
        with bootstrapped({
            'git'        : 'GitPython',
            'github'     : 'PyGithub',
            'mdutils'    : 'MdUtils',
            'pipreqs'    : 'pipreqs',
            #'tomli'      : 'tomli',
            'tomli_w'    : 'tomli_w', }):
            #import git
            #import github
            #import mdutils
            #import pipreqs
            #import tomli
            #import tomli_w
            git_ignore      :Path          = root / '.gitignore'
            ensure_synchronized_source(root)
            create_gitignore_if_not_exists(git_ignore, clobber=True)
            transition_to_compiled(root, name, clobber=True) # TODO needs to return the wheel(s)
            #transition_to_deb(root, wheel, name) # TODO needs the wheel(s)
    if not mode.is_bundled:
        with bootstrapped({
            'git'        : 'GitPython',
            'github'     : 'PyGithub',
            'PyInstaller': 'PyInstaller', }):
            #import PyInstaller
            transition_to_bundled(root, name, clobber=True)
    #if not mode.is_installed:
    #    raise NotImplementedError()
    # TODO else build & install target (i.e, not self)

    raise NotImplementedError()

# TODO config dataclass ==> autogen __doc__ ==> docopt
def main()->None:
    #bootstrap_environment()

    root            :Path          = Path(os.getcwd()).resolve()
    name            :str           = root.name
    bootstrap_execution_mode(root, name)
    sys.exit(0)








    # TODO perf & process management






    # TODO
    #ensure_system_dependencies ...
    #linux-perf                                 \
    #autofdo                                    \

    # TODO perf:
    # - discover targets, spawn & monitor
    # - discover targets, find their already-running processes & monitor

    # TODO indexing:
    # - index project
    # - index imported 3rd party and stdlib
    # - index man pages

##def main() -> None:
##    # Initial setup
##    setup_logging_if_necessary(get_simple_name())
##
##    # Define our desired reality
##    target = EnvState(is_root=True, is_venv=True, is_docker=True, is_raw=True)
##
##    # The Bootstrapper handles the 'Climb'
##    # Each call to reach_target() checks where we are and jumps if needed.
##    orc = Bootstrapper(target)
##
##    # Stage 1: Get into Venv
##    with bootstrapped({'venv': 'venv'}):
##        orc.reach_target()
##
##    # Stage 2: Get Root (Inside Venv)
##    orc.reach_target()
##
##    # Stage 3: Get Docker (As Root, Inside Venv)
##    with bootstrapped({'python_on_whales': 'python-on-whales'}):
##        orc.reach_target()
##
##    # --- If we are here, we are in the "Desired Ending State" ---
##
##    # Final App Setup
##    with bootstrapped({'dotenv': 'dotenv', 'lib_programname': 'lib-programname'}) as modules:
##        modules['dotenv'].load_dotenv()
##        clear_and_setup_logging(get_sophisticated_name())
##
##        mode = get_execution_mode()
##        if mode['is_raw']:
##            logging.info("🛠️ Running in development (raw) mode.")
##
##        logging.info("🚀 System is go.")
#
#def main() -> None:
#    # 1. Base identity
#    setup_logging_if_necessary(get_simple_name())
#
#    # 2. Define the Target Environment
#    # Note: Setting is_raw=True means we want to run as source.
#    # If we wanted to "self-compile", we'd eventually set is_compiled=True.
#    target = EnvState(
#        is_root=True,
#        is_venv=True,
#        is_docker=False,
#        is_chroot=False,
#        mode=ExecutionMode(
#            is_bundled=True,
#            is_compiled=True,
#            is_installed=True,
#            is_raw=False,
#        )
#    )
#
#    boot = Bootstrapper(target)
#
#    # 3. The Convergent Climb
#    # Each stage ensures the *tools* for the next jump exist, then calls reach_target
#
#    # Step A: Venv (requires no special host tools other than python)
#    with bootstrapped({'venv': 'venv'}):
#        boot.reach_target()
#
#    # Step B: Root (Inside Venv)
#    boot.reach_target()
#
#    # Step C: Docker (Inside Venv, as Root)
#    # We need whales to build/run the container
#    with bootstrapped({'python_on_whales': 'python-on-whales'}):
#        boot.reach_target()
#
#    # 4. Success: The Desired State
#    # We only get here if current == target (mostly)
#    with bootstrapped({'dotenv': 'dotenv', 'lib_programname': 'lib_programname'}) as modules:
#        modules['dotenv'].load_dotenv()
#        logging.error(f'environ: {"\n".join(os.environ.values())}')
#
#        # Now that we have lib_programname, we can get the fancy ID
#        final_name = get_sophisticated_name()
#        clear_and_setup_logging(final_name)
#
#        current_mode = get_execution_mode()
#        if current_mode.is_raw:
#            logging.info("🛠️ System operating in RAW mode (Source code).")
#
#        logging.info("🚀 All systems nominal. Entrypoint complete.")
#        # Proceed to actual business logic...

if __name__ == '__main__':
    main()

