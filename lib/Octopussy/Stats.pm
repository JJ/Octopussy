
=head1 NAME

Octopussy::Stats - Octopussy System Stats module

=cut

package Octopussy::Stats;

use strict;
use warnings;

use Readonly;
use Sys::CPU;

use Octopussy::Cache;
use Octopussy::Storage;

Readonly my $KBYTE => 1024;

=head1 FUNCTIONS

=head2 CPU_Info()

Returns the CPU Information

=cut 

sub CPU_Info
{
    my $cnt = Sys::CPU::cpu_count();
    my $info = ($cnt > 1 ? "$cnt X " : '') . Sys::CPU::cpu_type();

    return ($info);
}

=head2 CPU_Usage()

Returns the CPU Usage (user/system/idle/wait in percent)

=cut

sub CPU_Usage
{
    my $line = `vmstat 1 2 | tail -1`;

    if ($line =~ /.+\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)$/)
    {
        return ({user => $1, system => $2, idle => $3, wait => $4});
    }

    return (undef);
}

=head2 Load()

Returns System Load (information from /proc/loadavg)

=cut

sub Load
{
    if (defined open my $PROC, '<', '/proc/loadavg')
    {
        my $line = <$PROC>;
        close $PROC;

        return ($1)
            if ($line =~ /^(\S+)/);
    }

    return (undef);
}

=head2 Mem_Total()

Returns the Total of Memory in MegaBytes (information from /proc/meminfo)

=cut

sub Mem_Total
{
    if (defined open my $PROC, '<', '/proc/meminfo')
    {
        my @lines = <$PROC>;
        close $PROC;
        while (my $line = shift @lines)
        {
            return (int($1 / $KBYTE))    ## no critic
                if ($line =~ /^MemTotal:\s+(\d+)/);
        }
    }

    return (undef);
}

=head2 Mem_Usage()

Returns the Memory usage in this format: "$used M / $total M ($percent%)"

=cut 

sub Mem_Usage
{
    if (defined open my $PROC, '<', '/proc/meminfo')
    {
        my @lines = <$PROC>;
        close $PROC;
        my ($free, $total) = (0, 0);
        while (my $line = shift @lines)
        {
            if ($line =~ /^MemTotal:\s+(\d+)/)
            {
                $total = int($1 / $KBYTE);    ## no critic
            }
            if ($line =~ /^MemFree:\s+(\d+)/)
            {
                $free = int($1 / $KBYTE);     ## no critic
            }
        }
        return ('No Memory Detected') if ($total == 0);
        my $percent = int(($total - $free) / $total * 100);    ## no critic

        return (($total - $free) . " used M / $total M ($percent%)");
    }

    return (undef);
}

=head2 Swap_Usage()

Returns the Swap usage in this format: "$used M / $total M ($percent%)"

=cut 

sub Swap_Usage
{
    if (defined open my $PROC, '<', '/proc/meminfo')
    {
        my @lines = <$PROC>;
        close $PROC;
        my ($free, $total) = (0, 0);
        while (my $line = shift @lines)
        {
            if ($line =~ /^SwapTotal:\s+(\d+)/)
            {
                $total = int($1 / 1024);    ## no critic
            }
            if ($line =~ /^SwapFree:\s+(\d+)/)
            {
                $free = int($1 / 1024);     ## no critic
            }
        }
        return ('No Swap Detected') if ($total == 0);
        my $percent = int(($total - $free) / $total * 100);    ## no critic

        return (($total - $free) . " used M / $total M ($percent%)");
    }

    return (undef);
}

=head2 Partition_Logs

=cut

sub Partition_Logs
{
    my @storages = Octopussy::Storage::Configurations();
    my @result   = ();
    my %dir;
    my @lines = `df -k`;

    foreach my $l (@lines)
    {
        $dir{"$2"} = $1
            if ($l =~ /^(?:\S+)?\s+\S+\s+\S+\s+\S+\s+(\d+\%)\s+(\S+)/);
    }
    foreach my $s (@storages)
    {
        my $d = $s->{directory};
	next	if (!defined $d);
        my $match = 0;
        while (($d =~ /^(.*)\//) && (!$match))
        {
            if (defined $dir{$d})
            {
                push @result, {directory => $s->{s_id}, usage => $dir{$d}};
                $match = 1;
            }
            else
            {
                $d =~ s/^(.*)\/(.+)*$/$1/g;
                $d = ($d eq '' ? '/' : $d);
                if ($d =~ /^\/$/)
                {
                    push @result, {directory => $s->{s_id}, usage => $dir{$d}};
                    $match = 1;
                }
            }
        }
    }

    return (@result);
}

=head2 Events()

Returns Stats Events

=cut 

sub Events
{
    my %device;

    my $cache = Octopussy::Cache::Init('octo_dispatcher');
    my $time  = $cache->get('dispatcher_stats_datetime');
    my $stats = $cache->get('dispatcher_stats_devices');
    foreach my $k (keys %{$stats}) { $device{$k} = $stats->{$k}; }

    return ($time, \%device);
}

1;

=head1 AUTHOR

Sebastien Thebert <octopussy@onetool.pm>

=cut
