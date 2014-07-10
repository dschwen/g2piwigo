#!/usr/bin/perl

my $usage = "\n
    in the piwigo galleries folder do\n
    find | grep -v /thumbnail | grep -v /pwg_high | cut -c3- | ../convertcomments.pl --menalto-dbname=gl2_database --menalto-dbuser= --menalto-dbpass=gl2_db_password --menalto-table-prefix=gl2_ --menalto-column-prefix=g_ --piwigo-dbname=piwigo_database --piwigo-dbuser=piwigo --piwigo-dbpass=piwigo_db_password\n";

use DBI;
use DBD::mysql;
use Getopt::Long;

my @opt_mandatory = qw/
    menalto-dbname=s
    menalto-dbuser=s
    menalto-dbpass=s
    piwigo-dbname=s
    piwigo-dbuser=s
    piwigo-dbpass=s
/;

my @opt_optional = qw/
    menalto-dbhost=s
    menalto-table-prefix=s
    menalto-column-prefix=s
    piwigo-dbhost=s
    piwigo-prefix=s
/;

my %opt = ();
GetOptions(
    \%opt,
    @opt_mandatory,
    @opt_optional
);

# use Data::Dumper; print Dumper(\%opt); exit();

foreach my $param (@opt_mandatory) {
    $param =~ s/=s$//;
    if (not defined $opt{$param}) {
        print '--'.$param.' is mandatory'."\n";
        print $usage;
        exit();
    }
}

if (not defined $opt{'menalto-dbhost'}) {
    $opt{'menalto-dbhost'} = 'localhost';
}

if (not defined $opt{'menalto-table-prefix'}) {
    $opt{'menalto-table-prefix'} = 'g_';
}

if (not defined $opt{'menalto-column-prefix'}) {
    $opt{'menalto-column-prefix'} = '';
}

if (not defined $opt{'piwigo-dbhost'}) {
    $opt{'piwigo-dbhost'} = 'localhost';
}

if (not defined $opt{'piwigo-prefix'}) {
    $opt{'piwigo-prefix'} = '';
}

$ds1 = "dbi:mysql:".$opt{'menalto-dbname'}.":".$opt{'menalto-dbhost'}.":3306";
$db1 = DBI->connect( $ds1, $opt{'menalto-dbuser'}, $opt{'menalto-dbpass'}, { PrintError => 1})
    or die $DBI::errstr;

$ds2 = "dbi:mysql:".$opt{'piwigo-dbname'}.":".$opt{'piwigo-dbhost'}.":3306";
$db2 = DBI->connect( $ds2, $opt{'piwigo-dbuser'}, $opt{'piwigo-dbpass'}, { PrintError => 1})
    or die $DBI::errstr;

# Gallery2 parent Ids (root is always 7!)
@ids = ( 7,0,0,0,0,0 );
# piwigo uppercats
@uct = ( "NULL",0,0,0,0,0 );
@ranks = ();

while(<STDIN>) {
  s/\n//g;
  $dir = $_;
  @path = split(/\//);
  $level = int(@path);
  next if( $level == 0 );

  $parentId = $ids[$level-1];

  # get id and title/summary/description of tail element in path
  $query = "
SELECT
    f.".$opt{'menalto-column-prefix'}."id,
    i.".$opt{'menalto-column-prefix'}."title,
    i.".$opt{'menalto-column-prefix'}."summary,
    i.".$opt{'menalto-column-prefix'}."description,
    i.".$opt{'menalto-column-prefix'}."canContainChildren,
    a.".$opt{'menalto-column-prefix'}."orderWeight,
    a.".$opt{'menalto-column-prefix'}."viewCount,
    FROM_UNIXTIME(e.".$opt{'menalto-column-prefix'}."creationTimestamp)
  FROM ".$opt{'menalto-table-prefix'}."Item i
    JOIN ".$opt{'menalto-table-prefix'}."FileSystemEntity f ON i.".$opt{'menalto-column-prefix'}."id = f.".$opt{'menalto-column-prefix'}."id
    JOIN ".$opt{'menalto-table-prefix'}."ChildEntity c ON f.".$opt{'menalto-column-prefix'}."id = c.".$opt{'menalto-column-prefix'}."id
    JOIN ".$opt{'menalto-table-prefix'}."ItemAttributesMap a ON i.".$opt{'menalto-column-prefix'}."id = a.".$opt{'menalto-column-prefix'}."itemId
    JOIN ".$opt{'menalto-table-prefix'}."Entity e ON e.".$opt{'menalto-column-prefix'}."id = i.".$opt{'menalto-column-prefix'}."id
  WHERE c.".$opt{'menalto-column-prefix'}."parentId = ".$db1->quote($parentId)."
    AND f.".$opt{'menalto-column-prefix'}."pathComponent=".$db1->quote($path[$level-1])."
;";

  $sth = $db1->prepare($query);
  $sth->execute;
  @row = $sth->fetchrow();
  $sth->finish;

  #print "$row[4] - $parentId -> $row[0] : $row[1] $row[2] $row[3]\n";
  $title = remove_bbcode($row[1]);
  $summary = remove_bbcode($row[2]);
  $description = remove_bbcode($row[3]);
  $weight = $row[5];
  $views = $row[6];
  $date_available = $row[7];
  $ids[$level] = $row[0];
  $pid{$row[0]}=$dir;

  if( $row[4] == 0 ) {
    # image
    $comment = "";
    if( $summary ne "" && $description ne "" ) {
      $comment = "<b>$summary</b> - $description";
    } else {
      if( $summary ne "" ) {
        $comment = $summary;
      } else {
        $comment = $description;
      }
    }

    $query = "
UPDATE ".$opt{'piwigo-prefix'}."images
  SET name=".$db2->quote($title)."
    , comment=".$db2->quote($comment)."
    , date_available='".$date_available."'
  WHERE path = ".$db2->quote("./galleries/".$dir)." ";
    print "$query\n";
    $sth = $db2->prepare($query);
    $sth->execute;
    $sth->finish;

    # build a map from gallery2 ids to piwigo image ids
    $query = "SELECT id FROM ".$opt{'piwigo-prefix'}."images WHERE path = ".$db2->quote("./galleries/".$dir);
    $sth = $db2->prepare($query);
    $sth->execute;
    ($iid{$row[0]}) = $sth->fetchrow();
    $sth->finish;

  } else {
    # folder
    $comment = "";
    if( $summary ne "" && $description ne "" ) {
      $comment = "$summary <!--complete--> $description";
    } else {
      if( $summary ne "" ) {
        $comment = $summary;
      } else {
        $comment = "<!--complete-->$description";
      }
    }

    # get piwigo category id
    $uc = "= ".$uct[$level-1];
    $uc = "IS NULL" if( $uct[$level-1] eq "NULL" );
    $query = "SELECT id FROM ".$opt{'piwigo-prefix'}."categories WHERE dir = ".$db2->quote($path[$level-1])." AND id_uppercat $uc";
    $sth = $db2->prepare($query);
    $sth->execute;
    @row = $sth->fetchrow();
    $sth->finish;
    $id = $row[0];
    $uct[$level] = $id;

    # build global_rank string
    $grank = "";
    for($i=1;$i<$level;$i++ ) {
      $grank .= $ranks[$i].".";
    }
    $grank .= $weight;
    $ranks[$level]=$weight;

    $query = "UPDATE ".$opt{'piwigo-prefix'}."categories SET name=".$db2->quote($title).", comment=".$db2->quote($comment).", rank=$weight, global_rank=".$db2->quote($grank)." WHERE id = $id";
    print "$query\n";
    $sth = $db2->prepare($query);
    $sth->execute;
    $sth->finish;

    # get highlight picture
    $query = "
SELECT d2.".$opt{'menalto-column-prefix'}."derivativeSourceId
  FROM ".$opt{'menalto-table-prefix'}."ChildEntity c
    JOIN ".$opt{'menalto-table-prefix'}."Derivative d1 ON c.".$opt{'menalto-column-prefix'}."id = d1.".$opt{'menalto-column-prefix'}."id
    JOIN ".$opt{'menalto-table-prefix'}."Derivative d2 ON d1.".$opt{'menalto-column-prefix'}."derivativeSourceId=d2.".$opt{'menalto-column-prefix'}."id
  WHERE c.".$opt{'menalto-column-prefix'}."parentId = ".$ids[$level];
    $sth = $db1->prepare($query);
    $sth->execute;
    ($hid{$id}) = $sth->fetchrow();
    $sth->finish;
 }
}

# apply highlites as representative images
while(($key, $value) = each(%hid)) {
  print "$key $value $pid{$value}\n";

  # get piwigo picture id
  $query="SELECT id from ".$opt{'piwigo-prefix'}."images WHERE path = ".$db2->quote("./galleries/".$pid{$value});
  print "$query\n";
  $sth = $db2->prepare($query);
  $sth->execute;
  ($id) = $sth->fetchrow();
  $sth->finish;

  $query = "UPDATE ".$opt{'piwigo-prefix'}."categories SET representative_picture_id =".$db2->quote($id)." WHERE id = ".$db2->quote($key);
  print "$query\n";
  $sth = $db2->prepare($query);
  $sth->execute;
  $sth->finish;
}

# copy comments
$query = "
SELECT
    c.".$opt{'menalto-column-prefix'}."parentId,
    t.".$opt{'menalto-column-prefix'}."subject,
    t.".$opt{'menalto-column-prefix'}."comment,
    t.".$opt{'menalto-column-prefix'}."author,
    t.".$opt{'menalto-column-prefix'}."date
  FROM ".$opt{'menalto-table-prefix'}."ChildEntity c
    JOIN ".$opt{'menalto-table-prefix'}."Comment t ON t.".$opt{'menalto-column-prefix'}."id = c.".$opt{'menalto-column-prefix'}."id
  WHERE t.".$opt{'menalto-column-prefix'}."publishStatus=0
";
$sth2 = $db1->prepare($query);
$sth2->execute;
while( ($id,$subject,$comment,$author,$date) = $sth2->fetchrow() ) {
  # FROM_UNIXTIME($date)
  if( $iid{$id} ) {
    if( $subject ne "" ) {
      $comment = "<b>$subject</b> $comment";
    }
    $query = "INSERT INTO ".$opt{'piwigo-prefix'}."comments (image_id,date,author,content,validated) VALUES (".$db2->quote($iid{$id}).",FROM_UNIXTIME($date),".$db2->quote($author).",".$db2->quote($comment).",True)";
    print "$query\n";
    $sth = $db2->prepare($query);
    $sth->execute;
    $sth->finish;
  }
}
$sth->finish;

sub remove_bbcode() {
  my ($title) = @_;

  $title =~ s{\[color=\w+\]}{}g;
  $title =~ s{\[/color\]}{}g;

  $title =~ s{\[b\]}{<b>}g;
  $title =~ s{\[/b\]}{</b>}g;
  $title =~ s{\[i\]}{<i>}g;
  $title =~ s{\[/i\]}{</i>}g;

  $title =~ s{\[url *= *([^\]]+)\]([^\[]+)\[/url\]}{<a href="\1">\2</a>}g;

  return $title;
}
