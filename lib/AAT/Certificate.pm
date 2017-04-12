package AAT::Certificate;

=head1 NAME

AAT::Certificate - AAT Certificate module

=cut

use strict;
use warnings;
use Readonly;

use File::Copy;
use File::Path qw(rmtree);

use AAT::Application;

Readonly my $CA_DAYS => 3650;
Readonly my $CIPHER  => 'rsa:1024';

Readonly my $CONF        => '/etc/aat/openssl.cnf';
Readonly my $CONF_CA     => '/var/run/aat/openssl_ca.cnf';
Readonly my $CONF_CLIENT => '/var/run/aat/openssl_client.cnf';
Readonly my $CONF_SERVER => '/var/run/aat/openssl_server.cnf';

Readonly my $OPENSSL  => '/usr/bin/openssl';
Readonly my $SSL_CA   => "$OPENSSL ca -batch";
Readonly my $SSL_REQ  => "$OPENSSL req -batch";
Readonly my $SSL_X509 => "$OPENSSL x509";

=head1 FUNCTIONS

=head2 Authority_Configuration($appli)

Returns the Authority configuration

=cut

sub Authority_Configuration
{
    my $appli = shift;
    my %conf  = ();

    my $dir_ca = AAT::Application::Directory($appli, 'certificate_authority');
    my @lines = `$SSL_X509 -text -noout -in $dir_ca/cacert.pem`;
    foreach my $line (@lines)
    {
        ## no critic
        if ($line =~
/Subject: C=(\w+), ST=(.+?), L=(.+?), O=(.+?), OU=(.+?), CN=(.+?)\/emailAddress=(\S+)$/
           )
        {
            (
                $conf{country}, $conf{state}, $conf{city}, $conf{org},
                $conf{org_unit}, $conf{common_name}, $conf{email}
            ) = ($1, $2, $3, $4, $5, $6, $7);
        }
        ## use critic
    }

    return (%conf);
}

=head2 Authority_Create($appli, \%conf)

Creates a Certificate Authority

=cut

sub Authority_Create
{
    my ($appli, $conf) = @_;

    my $dir_ca = AAT::Application::Directory($appli, 'certificate_authority');
    File::Path::rmtree($dir_ca);
    system "mkdir -p $dir_ca/{certs,crl,newcerts,private}";
    system "touch $dir_ca/index.txt";
    system "echo '01' > $dir_ca/serial";

    copy($CONF, "$CONF_CA.tmp");
    if (   (defined open my $FILE, '<', "$CONF_CA.tmp")
        && (defined open my $OUT, '>', $CONF_CA))
    {
        while (my $line = <$FILE>)
        {
            foreach my $k (keys %{$conf})
            {
                my $sub = '<' . uc($k) . '>';
                $line =~ s/$sub/$conf->{$k}/g;
            }
            print {$OUT} $line;
        }
        close $FILE;
        close $OUT;
        system
"$SSL_REQ -config $CONF_CA -passout pass:octo -x509 -newkey $CIPHER -days $CA_DAYS -keyout $dir_ca/private/cakey.pem -out $dir_ca/cacert.pem";
        chmod 0600, glob "$dir_ca/private/*";    ## no critic

        return ("$dir_ca/private");
    }

    return (undef);
}

=head2 Client_Create($appli, $file, $password, \%conf)

Creates a Client Certificate

=cut

sub Client_Create
{
    my ($appli, $file, $password, $conf) = @_;

    my $dir_ca = AAT::Application::Directory($appli, 'certificate_authority');
    my $info = AAT::Application::Info($appli);
    my ($uid, $gid) = (getpwnam $info->{user})[2,3];

    copy($CONF, "$CONF_CLIENT.tmp");
    if (   (defined open my $FILE, '<', "$CONF_CLIENT.tmp")
        && (defined open my $OUT, '>', $CONF_CLIENT))
    {
        while (<$FILE>)
        {
            my $line = $_;
            foreach my $k (keys %{$conf})
            {
                my $sub = '<' . uc($k) . '>';
                $line =~ s/$sub/$conf->{$k}/g;
            }
            $line =~ s/<DIR>/$dir_ca/g;
            print {$OUT} $line;
        }
        close $FILE;
        close $OUT;
        system
"$SSL_REQ -config $CONF_CLIENT -passout pass:octo -newkey $CIPHER -keyout ${file}.key -out ${file}.req";
        system
"$SSL_CA -config $CONF_CLIENT -passin pass:octo -in ${file}.req -out ${file}.pem";
        system
"$OPENSSL pkcs12 -export -passin pass:octo -passout pass:$password -in ${file}.pem -inkey ${file}.key -out ${file}.p12 -name '$conf->{common_name}'";
        chown $uid, $gid, "${file}.p12";

        return ("${file}.p12");
    }

    return (undef);
}

=head2 Server_Create()

Creates a Server Certificate

=cut

sub Server_Create
{
    my ($appli, $dest, $conf) = @_;

    my $dir_ca = AAT::Application::Directory($appli, 'certificate_authority');
    my $info = AAT::Application::Info($appli);
    my ($uid, $gid) = (getpwnam $info->{user})[2,3];

    copy($CONF, "$CONF_SERVER.tmp");
    if (   (defined open my $FILE, '<', "$CONF_SERVER.tmp")
        && (defined open my $OUT, '>', $CONF_SERVER))
    {
        while (<$FILE>)
        {
            my $line = $_;
            foreach my $k (keys %{$conf})
            {
                my $sub = '<' . uc($k) . '>';
                $line =~ s/$sub/$conf->{$k}/g;
            }
            $line =~ s/<DIR>/$dir_ca/g;
            print {$OUT} $line;
        }
        close $FILE;
        close $OUT;
        system
"$SSL_REQ -config $CONF_SERVER -newkey $CIPHER -keyout $dest/server.key -out $dest/server.req";
        system
"$SSL_CA -config $CONF_SERVER -in $dest/server.req -out $dest/server.crt";
        system
"$OPENSSL rsa -passout pass:octo -in $dest/server.key -out $dest/server.key";
        chown $uid, $gid, glob "$dest/*";

        return ("$dest/server.key");
    }

    return (undef);
}

1;

=head1 SEE ALSO

AAT(3), AAT::DB(3), AAT::Syslog(3), AAT::Theme(3), AAT::Translation(3), AAT::User(3)

=head1 AUTHOR

Sebastien Thebert <octopussy@onetool.pm>

=cut
