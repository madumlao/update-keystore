# update-keystore.sh
Script for making it easy to update Java Keystores. Because Java.

        Usage: update-keystore.sh -k KEYSTORE -p STOREPASS -c CERT -n NAME [-d] [-p KEY]
        Given an OpenDJ certificate KEYSTORE and STOREPASS, checks if CERT is installed as
        NAME. If not, installs CERT as NAME. If NAME already exists, replaces NAME
        with the provided CERT.

        Arguments:
          -k|--keystore KEYSTORE      jks keystore to update
          -p|--storepass STOREPASS    keystore password
          -P|--storepassfile FILE     file containing keystore password
          -c|--cert CERT              certificate to install / update
          -K|--privatekey KEY         private key (to create privatekeyentry)
          -n|--alias NAME             certificate alias in the keystore
          -d|--deletefirst            delete NAME from keystore before importing

        Example:
          update-keystore.sh -k keystore.jks -p 123 -c my.crt -n server.crt

          Install or update the certificate named server.crt in keystore.jks using
          my.crt as the certificate.

Given a JKS and a PEM certificate, imports the PEM certificate into the JKS if it doesn't already exist with the given alias. If the certificate has a private key, it's imported as a `PrivateKeyEntry`, otherwise, it's imported as a `trustedCertEntry`.

If the certificate to import has a private key, but the keystore only has a `trustedCertEntry`, the keystore entry will be replaced by the private key. However, if the certificate to import does not have a private key, but the keystore has a `PrivateKeyEntry`, the keystore entry will prevail.

If the `-d` or `--deletefirst` option is provided, a non-matching keystore entry will be deleted first. If not provided (the default), then it will attempt to import the certificate into the keystore without deleting first.
