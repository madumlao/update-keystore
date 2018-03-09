#!/bin/bash
# updates a jks file to import a cert if it isnt updated

set -e	# exit on error

print_usage() {
	cat <<-END
	Usage: $(basename $0) -k KEYSTORE -p STOREPASS -c CERT -n NAME [-d] [-p KEY]
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
	  $(basename $0) -k keystore.jks -p 123 -c my.crt -n server.crt

	  Install or update the certificate named server.crt in keystore.jks using
	  my.crt as the certificate.
	END
}

get_jks_certexists() {
	KEYSTORE="$1"
	STOREPASS="$2"
	CERTNAME="$3"
	CERTKEY="$4"

	if ! [ "$CERTKEY" ]; then
		keytool -list \
			-keystore "$KEYSTORE" \
			-storepass "$STOREPASS" 2>/dev/null |\
			grep -q ^"$CERTNAME", -A1
	else
		keytool -list \
			-keystore "$KEYSTORE" \
			-storepass "$STOREPASS" 2>/dev/null |\
			grep -q ^"$CERTNAME"',.*PrivateKeyEntry,' -A1
	fi
}

get_jks_sha1() {
	KEYSTORE="$1"
	STOREPASS="$2"
	CERTNAME="$3"
	keytool -list \
		-keystore "$KEYSTORE" \
		-storepass "$STOREPASS" 2>/dev/null |\
		grep ^"$CERTNAME" -A1 |\
		grep SHA1 |cut -f 4 -d ' '|\
		tr -d :|\
		tr '[:upper:]' '[:lower:]'
}

get_pem_sha1() {
	CERTFILE="$1"
	openssl x509 -in "$CERTFILE" -noout -sha1 -fingerprint | \
		cut -f 2 -d = | \
		tr -d : |\
		tr '[:upper:]' '[:lower:]'
}

update_jks() {
	KEYSTORE="$1"
	STOREPASS="$2"
	CERTNAME="$3"
	CERTFILE="$4"
	CERTKEY="$5"

	if [ "$CERTKEY" = "" ]; then
		keytool -importcert \
			-keystore "$KEYSTORE" \
			-storepass "$STOREPASS" \
			-alias "$CERTNAME" \
			-file "$CERTFILE" \
			-noprompt
	else
		# private key provided, generate and import a p12 file
		P12STORE="$KEYSTORE".p12
		openssl pkcs12 -export \
			-name "$CERTNAME" \
			-in "$CERTFILE" \
			-inkey "$CERTKEY" \
			-out "$P12STORE" \
			-passout pass:"$STOREPASS"

		keytool -importkeystore \
			-srckeystore "$P12STORE" \
			-srcstorepass "$STOREPASS" \
			-destkeystore "$KEYSTORE" \
			-deststorepass "$STOREPASS" \
			-noprompt
	fi
}

delete_jks_cert() {
	KEYSTORE="$1"
	STOREPASS="$2"
	CERTNAME="$3"
	keytool -delete \
		-keystore "$KEYSTORE" \
		-storepass "$STOREPASS" \
		-alias "$CERTNAME"
}


# Process arguments
while [ "$1" != "" ]; do
	case "$1" in
		-k | --keystore )
			KEYSTORE="$2"
			shift 2;;
		-p | --storepass )
			STOREPASS="$2"
			shift 2;;
		-P | --storepassfile )
			STOREPASSFILE="$2"
			shift 2;;
		-c | --cert )
			CERTFILE="$2"
			shift 2;;
		-K | --privatekey )
			CERTKEY="$2"
			shift 2;;
		-n | --alias )
			CERTNAME="$2"
			shift 2;;
		-d | --deletefirst )
			DELETEFIRST=1
			shift 1;;
		-h | --help )
			ACTION=help
			break;;
		*) break ;;
	esac
done

if [ "$ACTION" = "" ] && [ "$KEYSTORE" = "" ]; then
	ACTION=error
fi

if [ "$ACTION" = "help" ] || [ "$ACTION" = "error" ]; then
	print_usage;
fi

if [ "$ACTION" = "error" ]; then
	exit 1
fi

if [ "$ACTION" = "" ]; then
	ACTION="update"
fi

if [ "$ACTION" = "update" ]; then
	# set keystore password
	if ! [ "$STOREPASS" ] && [ "$STOREPASSFILE" ]; then
		if ! [ -f "$STOREPASSFILE" ]; then
			echo "Unable to read provided keystore password file $STOREPASSFILE"
			exit 1
		fi

		STOREPASS="$(cat "$STOREPASSFILE")"	
	fi

	# error checking
	test -r "$CERTFILE" || ( echo "Cannot open certificate $CERTFILE" && exit 1 )
	test -n "$CERTNAME" || ( echo "No certificate name provided" && exit 1 )


	# begin update logic
	EXISTS=
	REPLACE=

	if ! get_jks_certexists "$KEYSTORE" "$STOREPASS" "$CERTNAME" "$CERTKEY"; then
		REPLACE=y
		echo $CERTNAME does not exist in $KEYSTORE, importing
	else
		EXISTS=y
		KEYSTORE_HASH="$(get_jks_sha1 "$KEYSTORE" "$STOREPASS" "$CERTNAME")"
		CERTFILE_HASH="$(get_pem_sha1 "$CERTFILE")"

		if [ "$KEYSTORE_HASH" = "$CERTFILE_HASH" ]; then
			echo Keystore hash matches Certfile hash, no change needed
		else
			REPLACE=y
			echo $KEYSTORE_HASH does not match $CERTFILE_HASH, replacing $CERTNAME
		fi
	fi

	if [ "$REPLACE" ]; then
		if [ "$DELETEFIRST" ]; then
			if [ "$EXISTS" ]; then
				echo "Deleting cert $CERTNAME before updating"
				delete_jks_cert "$KEYSTORE" "$STOREPASS" "$CERTNAME"
			fi
		fi

		update_jks "$KEYSTORE" "$STOREPASS" "$CERTNAME" "$CERTFILE" "$CERTKEY"
	fi
fi
