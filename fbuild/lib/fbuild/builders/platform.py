import platform
import os
from collections import OrderedDict

import fbuild
import fbuild.builders
import fbuild.db

# ------------------------------------------------------------------------------

class UnknownPlatform(fbuild.ConfigFailed):
    def __init__(self, platform=None):
        self.platform = platform

    def __str__(self):
        if self.platform is None:
            return 'cannot determine platform'
        else:
            return 'unknown platform: "%s"' % self.platform

# ------------------------------------------------------------------------------

# map of architecture names to match against
# please keep most specific names above more general ones (matching occurs 
# top down)
archmap = OrderedDict([
    ('irix64',    {'posix', 'irix', 'irix64'}),
    ('irix',      {'posix', 'irix'}),
    ('unix',      {'posix'}),
    ('posix',     {'posix'}),
    ('gnu/linux', {'posix', 'linux'}),
    ('linux',     {'posix', 'linux'}),
    ('solaris',   {'posix', 'solaris'}),
    ('sunos',     {'posix', 'solaris', 'sunos'}),
    ('nocygwin',  {'posix', 'cygwin', 'nocygwin'}),
    ('cygwin',    {'posix', 'cygwin'}),
    ('mingw',     {'posix', 'mingw'}),
    ('windows',   {'windows', 'win32'}),
    ('nt',        {'windows', 'win32', 'nt'}),
    ('win32',     {'windows', 'win32'}),
    ('win64',     {'windows', 'win64'}),
    ('windows32', {'windows', 'win32'}),
    ('windows64', {'windows', 'win64'}),
    ('freebsd',   {'posix', 'bsd', 'freebsd'}),
    ('netbsd',    {'posix', 'bsd', 'netbsd'}),
    ('openbsd',   {'posix', 'bsd', 'openbsd'}),
    ('darwin',    {'posix', 'bsd', 'darwin', 'macosx'}),
    ('osx',       {'posix', 'bsd', 'darwin', 'macosx'}),

    ('iphone-simulator', {'posix', 'bsd', 'darwin', 'iphone', 'simulator'}),
    ('iphone-sim',       {'posix', 'bsd', 'darwin', 'iphone', 'simulator'}),
    ('iphone',           {'posix', 'bsd', 'darwin', 'iphone'}),
])

# ------------------------------------------------------------------------------

@fbuild.db.caches
def guess_platform(ctx, arch=None):
    """L{guess_platform} returns a platform set that describes the various
    features of the specified I{platform}. If I{platform} is I{None}, try to
    determine which platform the system is and return that value. If the
    platform cannot be determined, return I{None}."""

    ctx.logger.check('determining platform')

    architecture = None

    # if no arch available, try to get one from the system
    if arch is None:
        # First lets see if uname exists
        try:
            uname = fbuild.builders.find_program(ctx, ['uname'], quieter=1)
        except fbuild.builders.MissingProgram:
            # Maybe we're on windows. Let's just use what python thinks is the
            # platform.
            #arch = os.name
            arch = platform.system().lower()
        else:
            # We've got uname, so let's see what platform it thinks we're on.
            try:
                stdout, stderr = ctx.execute((uname, '-s'), quieter=1)
            except fbuild.ExecutionError:
                # Ack, that failed too. Just fall back to python.
                #arch = os.name
                arch = platform.system().lower()
            else:
                arch = stdout.decode('utf-8').strip().lower()
                if arch == 'windowsnt' or 'mingw' in arch: arch = 'windows'

    # now search for the general "kind" of platform
    for key in archmap.keys():
        if key.lower() in arch.lower():
            architecture = archmap[key]
            break

    # no match, raise error
    if architecture is None:
        ctx.logger.failed()
        raise UnknownPlatform(arch)

    # we should have an architecture here
    ctx.logger.passed(architecture)
    return frozenset(architecture)

# ------------------------------------------------------------------------------

def obj_suffix(ctx, platform=None):
    platform = platform if platform else guess_platform(ctx)
    if 'windows' in platform:
        return '.obj'
    else:
        return '.o'

# ------------------------------------------------------------------------------

def static_obj_suffix(ctx, platform=None):
    platform = platform if platform else guess_platform(ctx)
    if 'windows' in platform:
        return '_static.obj'
    else:
        return '.o'

def static_lib_prefix(ctx, platform=None):
    platform = platform if platform else guess_platform(ctx)
    if 'windows' in platform:
        return ''
    else:
        return 'lib'

def static_lib_suffix(ctx, platform=None):
    platform = platform if platform else guess_platform(ctx)
    if 'windows' in platform:
        return '.lib'
    else:
        return '.a'

# ------------------------------------------------------------------------------

def shared_obj_suffix(ctx, platform=None):
    platform = platform if platform else guess_platform(ctx)
    if 'windows' in platform:
        return '_shared.obj'
    else:
        return '.os'

def shared_lib_prefix(ctx, platform=None):
    platform = platform if platform else guess_platform(ctx)
    if 'windows' in platform:
        return ''
    else:
        return 'lib'

def shared_lib_suffix(ctx, platform=None):
    platform = platform if platform else guess_platform(ctx)
    if 'windows' in platform:
        return '.dll'
    elif 'darwin' in platform:
        return '.dylib'
    else:
        return '.so'

# ------------------------------------------------------------------------------

def exe_suffix(ctx, platform=None):
    platform = platform if platform else guess_platform(ctx)
    if 'windows' in platform:
        return '.exe'
    else:
        return ''

# ------------------------------------------------------------------------------

def runtime_env_libpath(ctx, platform=None):
    platform = platform if platform else guess_platform(ctx)
    if 'windows' in platform:
        return 'PATH'
    elif 'darwin' in platform:
        return 'DYLD_LIBRARY_PATH'
    else:
        return 'LD_LIBRARY_PATH'
