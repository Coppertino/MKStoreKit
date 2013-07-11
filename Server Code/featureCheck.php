<?php
	include_once('common.inc.php');
	
	header('Content-Type: text/plain'); 
	$prod = filter_input(INPUT_POST,'productid',FILTER_SANITIZE_STRING); // varchar(255)
	$udid = filter_input(INPUT_POST,'udid',FILTER_SANITIZE_STRING); // varchar(255)
	
	 /*
	*  Setup MySQL
	*/
	$sql = mysql_connect(DB_HOST, DB_USER, DB_PASS) or die("Unable to connect");
	mysql_select_db(DB_NAME, $sql) or die ("Unable to select database");
	
	$query = sprintf("SELECT * FROM inapp_requests AS r LEFT JOIN inapp_products AS p ON r.product_id = p.id
					WHERE r.udid = '%s' AND p.productId = '%s' AND r.status = 1",
					mysql_real_escape_string($udid), mysql_real_escape_string($prod));
	$res = mysql_query($query, $sql) or die ("Unable to select :-(");
	$num = mysql_num_rows($res);
		
	if($num == 0)
		$returnString = "NO";
	else
		$returnString = "YES";
		
	mysql_close($sql);
	echo $returnString;
?>
