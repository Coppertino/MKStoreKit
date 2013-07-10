<?php
	include_once('common.inc.php');
	header('Content-type: application/json');

	$devmode = TRUE; // change this to FALSE after testing in sandbox
		
	$receiptdata = $_POST['receiptdata'];	
	$appleURL = (isset($devmode) && $devmode) ? "https://sandbox.itunes.apple.com/verifyReceipt" : "https://buy.itunes.apple.com/verifyReceipt";

	if (isset($devmode) && $devmode) {
		ini_set('display_errors', 'On');
		error_reporting(E_ALL);
		
		logIt2("POST_DATA:".print_r($_POST, 1));
		logIt2("RECEIPTDATA:".$receiptdata);
	}	
	
	           
 	$receipt		= json_encode(array("receipt-data" => $receiptdata));
	$response_json	= do_post_request($appleURL, $receipt);
	$response		= json_decode($response_json);
	
	
	echo ($response->{'status'} == 0) ? json_encode(array('result' => true)) : json_encode(array('result' => false, 'error' => 'Fail to validate receipt with Apple'));

	/**************************
	***************************/
	
	function do_post_request($url, $data, $optional_headers = null)
	{
	  $params = array(
						'http' => array(
						'method' => 'POST',
						'content' => $data
	            ));
	            
	  if ($optional_headers !== null) {
	  		$params['http']['header'] = $optional_headers;
	  }
	  
	  $ctx = stream_context_create($params);
	  $fp = @fopen($url, 'rb', false, $ctx);
	  if (!$fp) {
	    throw new Exception("Problem with $url, $php_errormsg");
	  }
	  $response = @stream_get_contents($fp);
	  if ($response === false) {
	    throw new Exception("Problem reading data from $url, $php_errormsg");
	  }
	  return $response;
	}
	
	function logIt2($msg)
	{
		logIt('/tmp/DEBUG-'.basename(__FILE__).'.log', 
		'['.date('Y-m-d H:i:s').'L:'.__LINE__.']:'.$msg
		);
	}
	

?>

