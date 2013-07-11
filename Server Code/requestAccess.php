	
<?php
include_once('common.inc.php');
	
	$prod = filter_input(INPUT_POST, 'productid', FILTER_SANITIZE_NUMBER_INT);
	$udid = filter_input(INPUT_POST, 'udid', FILTER_SANITIZE_STRING);
	$email = filter_input(INPUT_POST, 'email', FILTER_SANITIZE_EMAIL);
	$message = filter_input(INPUT_POST, 'message', FILTER_SANITIZE_ENCODED);

    /*
	*  Setup MySQL
	*/
	$sql = mysql_connect(DB_HOST, DB_USER, DB_PASS) or die("Unable to connect");
	mysql_select_db(DB_NAME, $sql) or die ("Unable to select database");
	
	$lastid = '';
	$result = 'error';
	
	if (!empty($prod) && !empty($udid) && !empty($email)) {
	    $query = sprintf("INSERT INTO inapp_requests(product_id, udid, email, message, status, lastUpdated) 
	    					VALUES (%d, '%s', '%s', '%s', 0, CURRENT_TIMESTAMP())
	    					ON DUPLICATE KEY UPDATE lastUpdated = CURRENT_TIMESTAMP(), email = '%s', message = '%s', status = '0'",
	    					$prod, mysql_real_escape_string($udid), mysql_real_escape_string($email), mysql_real_escape_string($message),
	    					mysql_real_escape_string($email), mysql_real_escape_string($message)
	    					);
	    					
		
	 	
	 	$result = "ok";
		
	}

	
 	mysql_close($sql);
 	die($result);

?>
