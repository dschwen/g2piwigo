#!/usr/bin/perl

if( int(@ARGV) != 4 ) {
  print "
    in the piwigo galleries folder do
    find |grep -v /thumbnail | cut -c3- | ../convertcomments.pl g2_database g2_db_password piwigo_database piwigo_db_password\n";
  exit;
}

use DBI;
use DBD::mysql;

$ds1 = "dbi:mysql:wikimini_gallery2:localhost:3306";
$db1 = DBI->connect( $ds1, $ARGV[0], $ARGV[1],
                  { PrintError => 1}) || die $DBI::errstr;

$ds2 = "dbi:mysql:wikimini_piwigo:localhost:3306";
$db2 = DBI->connect( $ds2, $ARGV[2], $ARGV[3],
                  { PrintError => 1}) || die $DBI::errstr;

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
      f.g_id, i.g_title, i.g_summary, i.g_description, i.g_canContainChildren, a.g_orderWeight, a.g_viewCount 
    FROM 
      g2_FileSystemEntity f, g2_ChildEntity c, g2_Item i, g2_ItemAttributesMap a 
    WHERE 
      i.g_id = f.g_id AND 
      f.g_id = c.g_id AND 
      i.g_id = a.g_itemId AND
      c.g_parentId = ".$db1->quote($parentId)." AND 
      f.g_pathComponent=".$db1->quote($path[$level-1]).";
    ";
  $sth = $db1->prepare($query);
  $sth->execute;
  @row = $sth->fetchrow();
  $sth->finish;

  #print "$row[4] - $parentId -> $row[0] : $row[1] $row[2] $row[3]\n";
  $title = $row[1];
  $summary = $row[2];
  $description = $row[3];
  $weight = $row[5];
  $views = $row[6];
  $ids[$level] = $row[0];

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

    $query = "UPDATE piwigo_images SET name=".$db2->quote($title).", comment=".$db2->quote($comment)." WHERE path = ".$db2->quote("./galleries/".$dir)." ";
    print "$query\n";
    $sth = $db2->prepare($query);
    $sth->execute;
    $sth->finish;
  } else {
    # folder
    $comment = "";
    if( $summary ne "" && $description ne "" ) {
      $comment = "$summary <!--complete> $description";
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
    $query = "SELECT id FROM piwigo_categories WHERE dir = ".$db2->quote($path[$level-1])." AND id_uppercat $uc";
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

    $query = "UPDATE piwigo_categories SET name=".$db2->quote($title).", comment=".$db2->quote($comment).", rank=$weight, global_rank=".$db2->quote($grank)." WHERE id = $id";
    print "$query\n";
    $sth = $db2->prepare($query);
    $sth->execute;
    $sth->finish;

    # get highlight picture 
    $query = "
      SELECT d2.g_derivativeSourceId 
      FROM g2_ChildEntity c, g2_Derivative d1, g2_Derivative d2  
      WHERE c.g_id = d1.g_id 
      AND d1.g_derivativeSourceId=d2.g_id 
      AND c.g_parentId = ".$ids[$level];
 }
}
