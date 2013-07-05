<?php

	include_once('common.inc.php');
	header('Content-type: application/json');
	
	/*
	*  Setup MySQL
	*/
	$sql = mysql_connect(DB_HOST, DB_USER, DB_PASS) or die("Unable to connect");
	mysql_select_db(DB_NAME, $sql);
	
	if (INAPP_TEST && isset($_GET['test'])) {
		$code = 'INAPPTESTCODE';
		$product = 'com.coppertino.SampleInApp';
		$hwid = 'AA:AA:AA:AA:AA';
		$user = 'TestUser';
		$email = 'email@email.com';
		
	} else {
		if (!isset($_POST['code']) || empty($_POST['code']) ||
			!isset($_POST['hwid']) || empty($_POST['hwid']) ||
			!isset($_POST['productid']) || empty($_POST['productid']) ||
			!isset($_POST['name']) || empty($_POST['name']) ||
			!isset($_POST['email']) || empty($_POST['email'])
			) {
				$status_string = '400 Bad Request';
		        header($_SERVER['SERVER_PROTOCOL'] . ' ' . $status_string, true, 400);
				die();
			}
			
		$code = $_POST['code'];
		$hwid = $_POST['hwid'];
		$product = $_POST['productid'];
		$user = $_POST['name'];
		$email = $_POST['email'];
	}

	try {
		$codeRequest = requestValidCodeForProduct($code, $product);

		if (checkHardwareForRedeem($hwid, $code)) {
			echo(generateResult($product, $hwid));
		} elseif ($codeRequest['product_id'] > 0 && $codeRequest['code_id'] > 0 && $codeRequest['count'] > 0) {
			if (canUseRedeemFromReqeust($codeRequest) || true) {
				redeemRequestForUser($codeRequest, $hwid, $user, $email);
				echo(generateResult($product, $hwid));								
			} else {
				echo(json_encode(array("result" => false, "error" => "Redeem Code activations limit exceeded")));
			}
		} else {
			echo(json_encode(array("result" => false, "error" => "Redeem Code or Product not found")));
		}
		
		
	} catch (Exception $e) {
		echo 'Caught exception: ',  $e->getMessage(), "\n";
	}
		
	function requestValidCodeForProduct($code, $product) {
		$q = sprintf("SELECT c.id AS CID, p.id AS PID, p.productid, c.code, c.activations_count 
						FROM inapp_redeem_codes AS c
						LEFT JOIN inapp_products AS p ON c.product_id = p.id
						
						WHERE 
							`code` LIKE '%s' AND 
							c.valid_date <= CURRENT_TIMESTAMP() AND 
							c.expiration_date > CURRENT_TIMESTAMP() AND 
							p.productid LIKE '%s' 
						
						LIMIT 1", 
						
						mysql_real_escape_string($code), 
						mysql_real_escape_string($product));
		
		$r = mysql_query($q);
		
		if (!$r) {
			throw new Exception("Query Error: ".mysql_error());
		}
		
		$result = array(
			"product_id" => -1,
			"code_id" => -1,
			"count" => -1
		);
		
		if (mysql_num_rows($r) > 0 && $row = mysql_fetch_assoc($r)) {
			$result["product_id"] = $row["PID"];
			$result["code_id"] = $row["CID"];
			$result["count"] = $row["activations_count"];
			
		}
		
		mysql_free_result($r);
		
		return $result;
	}
	
	function canUseRedeemFromReqeust($request) 
	{
		$count = $request['count'];
		$redeemId = $request['code_id'];
		
		$r = mysql_query(sprintf('SELECT count(1) AS count FROM inapp_redeem_usage WHERE redeem_id = %d HAVING count < 1', $redeemId));
		if (!$r) {
			throw new Exception("Query Error: ".mysql_error());
		}
		
		$result = mysql_num_rows($r) > 0;
		mysql_free_result($r);
		
		return $result;
	}
	
	function redeemRequestForUser($request, $user_hwid, $user_email, $user_name)
	{
		$redeemId = $request['code_id'];
		$r = mysql_query(sprintf("INSERT INTO inapp_redeem_usage(redeem_id, hwid, email, `name`) 
									VALUES(%d, '%s', '%s', '%s') 
									ON DUPLICATE KEY UPDATE issued = CURRENT_TIMESTAMP();",
									$redeemId,
									mysql_real_escape_string($user_hwid),
									mysql_real_escape_string($user_email),
									mysql_real_escape_string($user_name)
		));
		
		if (!$r) {
			throw new Exception("Query Error: ".mysql_error());
		}
		
		mysql_free_result($r);
	}
	
	function checkHardwareForRedeem($hwid, $redeem) 
	{
		$r = mysql_query(sprintf("SELECT issued FROM inapp_redeem_usage AS u 
									LEFT JOIN inapp_redeem_codes AS c ON u.redeem_id = c.id
								  WHERE c.code LIKE '%s' AND u.hwid LIKE '%s';",
								  mysql_real_escape_string($redeem),
								  mysql_real_escape_string($hwid)));
								  
				if (!$r) {
			throw new Exception("Query Error: ".mysql_error());
		}
		
		$result = mysql_num_rows($r) > 0;
		mysql_free_result($r);
		
		return $result;						  
								  
	}
	
	function generateResult($product, $hwid)
	{
		/*
		*	Setup OPEN SSL
		*/
		if (!$private_key = openssl_get_privatekey(SSL_PRIVATE_KEY)) die('Loading Private Key failed');

		$receipt = array(
			'product_id' => $product,
			'hwid' => $hwid, 
		);
		
		$sign = '';
		if (openssl_sign(json_encode($receipt), $sign, $private_key)) {
			return (json_encode(array("result" => true, 'receipt' => $receipt, 'sign' => base64_encode($sign))));
		} else {
			return (json_encode(array("result" => false, "error" => "Signature update fail: ".openssl_error_string())));
		}
	}
?>