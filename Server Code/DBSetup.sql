--
-- Table structure for table `inapp_products`
--

DROP TABLE IF EXISTS `inapp_products`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `inapp_products` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `productid` varchar(255) NOT NULL,
  `productName` varchar(30) NOT NULL,
  `productDesc` varchar(255) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=2 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `inapp_products`
--

LOCK TABLES `inapp_products` WRITE;
/*!40000 ALTER TABLE `inapp_products` DISABLE KEYS */;
INSERT INTO `inapp_products` VALUES (1,'com.coppertino.test','test inapp','inapp');
/*!40000 ALTER TABLE `inapp_products` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `inapp_redeem_codes`
--

DROP TABLE IF EXISTS `inapp_redeem_codes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `inapp_redeem_codes` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `product_id` int(11) NOT NULL,
  `code` varchar(45) NOT NULL,
  `activations_count` int(11) NOT NULL DEFAULT '1',
  `valid_date` timestamp NULL DEFAULT NULL,
  `expiration_date` timestamp NULL DEFAULT NULL,
  `notes` varchar(45) DEFAULT NULL,
  PRIMARY KEY (`id`,`product_id`,`code`,`activations_count`),
  UNIQUE KEY `id_UNIQUE` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `inapp_redeem_codes`
--

LOCK TABLES `inapp_redeem_codes` WRITE;
/*!40000 ALTER TABLE `inapp_redeem_codes` DISABLE KEYS */;
INSERT INTO `inapp_redeem_codes` VALUES (1,1,'INAPPTESTCODE',1,'2013-07-01 04:00:00','2013-09-01 04:00:00','Test Redeem');
/*!40000 ALTER TABLE `inapp_redeem_codes` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `inapp_redeem_usage`
--

DROP TABLE IF EXISTS `inapp_redeem_usage`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `inapp_redeem_usage` (
  `redeem_id` int(11) NOT NULL,
  `hwid` varchar(45) NOT NULL,
  `status` enum('active','invalid') NOT NULL DEFAULT 'active',
  `issued` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `email` varchar(45) DEFAULT NULL,
  `name` varchar(45) DEFAULT NULL,
  PRIMARY KEY (`redeem_id`,`hwid`,`issued`,`status`),
  UNIQUE KEY `hw_redeem_idx` (`redeem_id`,`hwid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;
--
-- Table structure for table `inapp_requests`
--

DROP TABLE IF EXISTS `inapp_requests`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `inapp_requests` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `product_id` int(11) NOT NULL,
  `udid` varchar(40) NOT NULL,
  `email` varchar(100) DEFAULT NULL,
  `message` varchar(1000) DEFAULT NULL,
  `status` tinyint(1) NOT NULL DEFAULT '0',
  `lastUpdated` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`,`product_id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `inapp_requests`
--

LOCK TABLES `inapp_requests` WRITE;
/*!40000 ALTER TABLE `inapp_requests` DISABLE KEYS */;
/*!40000 ALTER TABLE `inapp_requests` ENABLE KEYS */;
UNLOCK TABLES;
