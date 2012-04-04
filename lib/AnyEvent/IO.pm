=head1 NAME

AnyEvent::IO - the DBI of asynchronous I/O implementations

=head1 SYNOPSIS

   use AnyEvent::IO;

   io_load "/etc/passwd", sub {
      my ($data) = @_
         or die "/etc/passwd: $!";

      warn "/etc/passwd contains ", ($data =~ y/://) , " colons.\n";
   };

   # also import O_XXX flags
   use AnyEvent::IO qw(:DEFAULT :flags);

   my $filedata = AE::cv;

   io_open "/etc/passwd", O_RDONLY, 0, sub {
      my ($fh) = @_
         or die "/etc/passwd: $!";

      io_stat $fh, sub {
         @_ or die "/etc/passwd: $!";

         my $size = -s _;

         io_read $fh, $size, sub {
            my ($data) = @_
               or die "/etc/passwd: $!";

            $size == length $data
               or die "/etc/passwd: short read, file changed?";

            # mostly the same as io_load, above - $data contains
            # the file contents now.
            $filedata->($data);
         };
      };
   };

   my $passwd = $filedata->recv;
   warn length $passwd, " octets.\n";

=head1 DESCRIPTION

This module provides functions that do I/O in an asynchronous fashion. It
is to to I/O the same as L<AnyEvent> is to event libraries - it only
I<interfaces> to other implementations or to a portable pure-perl
implementation (that does not, however, do asynchronous I/O).

The only such implementation that is supported (or even known to the
author) is L<IO::AIO>, which is used automatically when it can be
loaded. If it is not available, L<AnyEvent::IO> falls back to its
(synchronous) pure-perl implementation.

Unlike L<AnyEvent>, which model to use is currently decided at module load
time, not at first use. Future releases might change this.

=head2 RATIONALE

While disk I/O often seems "instant" compared to, say, socket I/O, there
are many situations where your program can block for extended time periods
when doing disk I/O. For example, you access a disk on an NFS server and
it is gone - can take ages to respond again, if ever.  OR your system is
extremely busy because it creates or restores a backup - reading data from
disk can then take seconds. Or you use Linux, which for so many years has
a close-to-broken VM/IO subsystem that can often induce minutes or more of
delay for disk I/O, even under what I would consider light I/O loads.

Whatever the situation, some programs just can't afford to block for long
times (say, half a second or more), because they need to respond as fast
as possible.

For those cases, you need asynchronous I/O.

The problem is, AnyEvent itself sometimes reads disk files (for example,
when looking at F</etc/hosts>), and under the above situations, this can
bring your program to a complete halt even if your program otherwise
takes care to only use asynchronous I/O for everything (e.g. by using
L<IO::AIO>).

On the other hand, requiring L<IO::AIO> for AnyEvent is clearly
impossible, as AnyEvent promises to stay pure-perl, and the overhead of
IO::AIO for small programs would be immense, especially when asynchronous
I/O isn't even needed.

Clearly, this calls for an abstraction layer, and that is what you are
looking at right now :-)

=head2 ASYNCHRONOUS VS. NON-BLOCKING

Many people are continuously confused on what the difference is between
asynchronous I/O and non-blocking I/O. Those two terms are not well
defined, which often makes it hard to even talk about the difference. Here
is a short guideline that should leave you less confused:

Non-blocking I/O means that data is delivered by some external means,
automatically - that is, something I<pushes> data towards your file
handle without you having to do anything. Non-blocking means that if your
operating system currently has no data available for you, it will not wait
("block" as it would normally do), but immediately return with an error.

Your program can then wait for data to arrive.

Often, you would expect this to work for disk files as well - if the
data isn't already in memory, one might wait for it. While this is sound
reasoning, the POSIX API does not support this, because the operating
system does not know where and how much of data you want to read, and more
so, the OS already knows that data is there, it doesn't need to "wait"
until it arrives from some external entity.

So basically, while the concept is sound, the existing OS APIs do not
support this, it makes no sense to switch a disk file handle into
non-blocking mode - it will behave exactly the same as in blocking mode,
namely it will block until the data has been read from the disk.

Th alternative that actually works is usually called I<asynchronous>
I/O. Asynchronous, because the actual I/O is done while your program does
something else, and only when it is done will you get notified of it: You
only order the operation, it will be executed in the background, and you
will get notified of the outcome.

This works with disk files, and even with sockets and other sources that
you could use with non-blocking I/O instead. It is, however, not very
efficient when used with sources that could be driven in a non-blocking
way, it makes most sense when confronted with disk files.

=head1 IMPORT TAGS

By default, this module implements all C<io_>xxx functions. In addition,
the following import tags can be used:

   :io        all io_ functions, smae as :DEFAULT
   :flags     the fcntl open flags (O_CREAT, O_RDONLY, ...)

=head1 API NOTES

The functions in this module are not meant to be the most versatile or the
highest-performers. They are meant to be easy to use for common cases. You
are advised to use L<IO::AIO> directly when possible, which has a more
extensive and faster API. If, however, you just want to do some I/O with
the option of it being asynchronous when people need it, these functions
are for you.

All the functions in this module implement an I/O operation, usually with
the same or similar name as the Perl builtin that it mimics, but with
an C<io_> prefix.

Each function expects a callback as their last argument. The callback is
usually called with the result data or result code. An error is usually
signalled by passing no arguments to the callback, which is then free to
look at C<$!> for the error code.

This makes all of the following forms of error checking valid:

   io_open ...., sub {
      my $fh = shift   # scalar assignment - will assign undef on error
         or die "...";

      my ($fh) = @_    # list assignment - will be 0 elements on error
         or die "...";

      @_               # check the number of elements directly
         or die "...";

When a path is specified, this path I<must be an absolute> path, unless
you make certain that nothing in your process calls C<chdir> or an
equivalent function while the request executes.

Changing the C<umask> while any requests execute that create files (or
otherwise rely on the current umask) results in undefined behaviour -
likewise changing anything else that would change the outcome, such as
your effective user or group ID.

Unlike other functions in the AnyEvent module family, these functions
I<may> call your callback instantly, before returning. This should not be
a real problem, as these functions never return anything useful.

=cut

package AnyEvent::IO;

use AnyEvent (); BEGIN { AnyEvent::common_sense }

use base "Exporter";

our @IO_REQ = qw(
   io_load io_open io_close io_seek io_read io_write io_truncate
   io_utime io_chown io_chmod io_stat io_lstat
   io_link io_symlink io_readlink io_rename io_unlink
   io_mkdir io_rmdir io_readdir
);
*EXPORT = \@IO_REQ;
our @FLAGS = qw(O_RDONLY O_WRONLY O_RDWR O_CREAT O_EXCL O_TRUNC O_APPEND);
*EXPORT_OK = \@FLAGS;
our %EXPORT_TAGS = (flags => \@FLAGS, io => \@IO_REQ);

our $MODEL;

if ($MODEL) {
   AE::log 7 => "Found preloaded IO model '$MODEL', using it.";
} else {
   if ($ENV{PERL_ANYEVENT_IO_MODEL} =~ /^([a-zA-Z0-9:]+)$/) {
      if (eval { require "AnyEvent/IO/$ENV{PERL_ANYEVENT_IO_MODEL}.pm" }) {
         AE::log 7 => "Loaded IO model '$MODEL' (forced by \$ENV{PERL_ANYEVENT_IO_MODEL}), using it.";
      } else {
         undef $MODEL;
         AE::log 4 => "Unable to load IO model '$ENV{PERL_ANYEVENT_IO_MODEL}' (from \$ENV{PERL_ANYEVENT_IO_MODEL}):\n$@";
      }
   }

   unless ($MODEL) {
      if (eval { require IO::AIO; require AnyEvent::AIO; require AnyEvent::IO::IOAIO }) {
         AE::log 7 => "Autoloaded IO model 'IOAIO', using it.";
      } else {
         require AnyEvent::IO::PP;
         AE::log 7 => "Autoloaded IO model 'Perl', using it.";
      }
   }
}

=head1 GLOBAL VARIABLES AND FUNCTIONS

=over 4

=item $AnyEvent::IO::MODEL

Contains the package name of the backend I/O model in use - at the moment,
this is usually C<AnyEvent::IO::Perl> or C<AnyEvent::IO::IOAIO>.

=item io_load $path, $cb->($data)

Tries to open C<$path> and read its contents into memory (obviously,
should only be used on files that are "small enough"), then passes them to
the callback as a string.

Example: load F</etc/hosts>.

   io_load "/etc/hosts", sub {
      my ($hosts) = @_
         or die "/etc/hosts: $!";

      AE::log info => "/etc/hosts contains ", ($hosts =~ y/\n/), " lines\n";
   };

=item io_open $path, $flags, $mode, $cb->($fh)

Tries to open the file specified by C<$path> with the O_XXX-flags
C<$flags> (from the Fcntl module, or see below) and the mode C<$mode> (a
good value is 0666 for C<O_CREAT>, and C<0> otherwise).

The (normal, standard, perl) file handle associated with the opened file
is then passed to the callback.

This works very much like perl's C<sysopen> function.

Changing the C<umask> while this request executes results in undefined
behaviour - likewise changing anything else that would change the outcome,
such as your effective user or group ID.

To avoid having to load L<Fcntl>, this module provides constants
for C<O_RDONLY>, C<O_WRONLY>, C<O_RDWR>, C<O_CREAT>, C<O_EXCL>,
C<O_TRUNC> and C<O_APPEND> - you can either access them directly
(C<AnyEvent::IO::O_RDONLY>) or import them by specifying the C<:flags>
import tag (see SYNOPSIS).

=item io_close $fh, $cb->($success)

Closes the file handle (yes, close can block your process indefinitely)
and passes a true value to the callback on success.

Due to idiosyncrasies in perl, instead of calling C<close>, the file
handle might get closed by C<dup2>'ing another file descriptor over
it, that is, the C<$fh> might still be open, but can be closed safely
afterwards and must not be used for anything.

=item io_read $fh, $length, $cb->($data)

Tries to read C<$length> octets from the current position from C<$fh> and
passes these bytes to C<$cb>. Otherwise the semantics are very much like
those of perl's C<sysread>.

If less than C<$length> octets have been read, C<$data> will contain
only those bytes actually read. At EOF, C<$data> will be a zero-length
string. If an error occurs, then nothing is passed to the callback.

Obviously, multiple C<io_read>'s or C<io_write>'s at the same time on file
handles sharing the underlying open file description results in undefined
behaviour, due to sharing of the current file offset (and less obviously
so, because OS X is not thread safe and corrupts data when you try).

=item io_seek $fh, $offset, $whence, $callback->($offs)

Seeks the filehandle to the new C<$offset>, similarly to perl's
C<sysseek>. The C<$whence> are the traditional values (C<0> to count from
start, C<1> to count from the current position and C<2> to count from the
end).

The resulting absolute offset will be passed to the callback on success.

=item io_write $fh, $data, $cb->($length)

Tries to write the octets in C<$data> to the current position of C<$fh>
and passes the actual number of bytes written to the C<$cb>. Otherwise the
semantics are very much like those of perl's C<syswrite>.

If less than C<length $data> octets have been written, C<$length> will
reflect that. If an error occurs, then nothing is passed to the callback.

Obviously, multiple C<io_read>'s or C<io_write>'s at the same time on file
handles sharing the underlying open file description results in undefined
behaviour, due to sharing of the current file offset (and less obviouisly
so, because OS X is not thread safe and corrupts data when you try).

=item io_truncate $fh_or_path, $new_length, $cb->($success)

Calls C<truncate> on the path or perl file handle and passes a true value
to the callback on success.

=item io_utime $fh_or_path, $atime, $mtime, $cb->($success)

Calls C<utime> on the path or perl file handle and passes a true value to
the callback on success.

The special case of both C<$atime> and C<$mtime> being C<undef> sets the
times to the current time, on systems that support this.

=item io_chown $fh_or_path, $uid, $gid, $cb->($success)

Calls C<chown> on the path or perl file handle and passes a true value to
the callback on success.

If C<$uid> or C<$gid> can be specified as C<undef>, in which case the
uid or gid of the file is not changed. This differs from perl's C<chown>
builtin, which wants C<-1> for this.

=item io_chmod $fh_or_path, $perms, $cb->($success)

Calls C<chmod> on the path or perl file handle and passes a true value to
the callback on success.

=item io_stat $fh_or_path, $cb->($success)

=item io_lstat $path, $cb->($success)

Calls C<stat> or C<lstat> on the path or perl file handle and passes a
true value to the callback on success.

The stat data will be available by stat'ing the C<_> file handle
(e.g. C<-x _>, C<stat _> and so on).

=item io_link $oldpath, $newpath, $cb->($success)

Calls C<link> on the paths and passes a true value to the callback on
success.

=item io_symlink $oldpath, $newpath, $cb->($success)

Calls C<symlink> on the paths and passes a true value to the callback on
success.

=item io_readlink $path, $cb->($target)

Calls C<readlink> on the paths and passes the link target string to the
callback.

=item io_rename $oldpath, $newpath, $cb->($success)

Calls C<rename> on the paths and passes a true value to the callback on
success.

=item io_unlink $path, $cb->($success)

Tries to unlink the object at C<$path> and passes a true value to the
callback on success.

=item io_mkdir $path, $perms, $cb->($success)

Calls C<mkdir> on the path with the given permissions C<$perms> (when in
doubt, C<0777> is a good value) and passes a true value to the callback on
success.

=item io_rmdir $path, $cb->($success)

Tries to remove the directory at C<$path> and passes a true value to the
callback on success.

=item io_readdir $path, $cb->(\@names)

Reads all filenames from the directory specified by C<$path> and passes
them to the callback, as an array reference with the names (without a path
prefix). The F<.> and F<..> names will be filtered out first.

The ordering of the file names is undefined - backends that are capable
of it (e.g. L<IO::AIO>) will return the ordering that most likely is
fastest to C<stat> through, and furthermore put entries that likely are
directories first in the array.

If you need best performance in recursive directory traversal or when
looking at really big directories, you are advised to use L<IO::AIO>
directly, specifically the C<aio_readdirx> and C<aio_scandir> functions,
which have more options to tune performance.

=back

=head1 ENVIRONMENT VARIABLES

See the description of C<PERL_ANYEVENT_IO_MODEL> in the L<AnyEvent>
manpage.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

1

