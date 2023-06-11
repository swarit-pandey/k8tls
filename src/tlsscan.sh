#!/bin/bash

chk_cmd()
{
	if ! command -v $1 &>/dev/null; then
		echo "<$1> command not found"
		echo "$2"
		exit
	fi
}

prerequisites()
{
	chk_cmd openssl "Install OpenSSL"
}

usage()
{
	cat << EOF
Usage: $0 <options>

Options:
-f | --infile input file containing list of addresses (mandatory)
-j | --json output json file
-h | --help
EOF
	exit 1
}

parse_cmdargs()
{
	OPTS=`getopt -o f:j:h --long infile:,json:,help -n 'parse-options' -- "$@"`
	[[ $? -ne 0 ]] && usage
	eval set -- "$OPTS"
	while true; do
		case "$1" in
			-f | --infile ) infile="$2"; [[ ! -f $infile ]] && echo "$infile file not found" && exit 2; shift 2;;
			-j | --json ) jsonout="$2"; [[ -f $jsonout ]] && rm -f $jsonout; shift 2;;
			-h | --help ) usage; shift 1;;
			-- ) shift; break ;;
			* ) break ;;
		esac
	done
	[[ "$infile" == "" ]] && echo "No address list provided, use --infile <file>" && exit 2
}

jsonreport()
{
	[[ "$jsonout" == "" ]] && return
	if [ -f "$jsonout" ]; then
		echo -en "\t},\n" >> $jsonout
	else
		echo -en "[\n" > $jsonout
	fi
	cat << EOF >> $jsonout
	{
		"Address": "$TLS_Address",
		"Status": "$TLS_Status",
		"Protocol_version": "$TLS_Protocol_version",
		"Ciphersuite": "$TLS_Ciphersuite",
		"Hash_used": "$TLS_Hash_used",
		"Peer_certificate": "$TLS_Peer_certificate",
		"Server_Temp_Key": "$TLS_Server_Temp_Key",
		"Signature_type": "$TLS_Signature_type",
		"Verification": "$TLS_Verification"
EOF
}

jsontrailer()
{
	[[ ! -f "$jsonout" ]] && return
	echo -en "\n\t}\n]" >> $jsonout
}


scantls()
{
	# unset previous vars
	varlist=`set | grep "^TLS_" | sed 's/=.*//g'`
	varlist=`echo $varlist`
	unset $varlist

	tmp=/tmp/tls.out
	rm -f $tmp 2>/dev/null
	timeout 3s openssl s_client -connect "$1" -brief < /dev/null 2>$tmp
	ret=$?
#	echo "ret=$ret"
#	cat $tmp
	TLS_Address="$1"
	case "$ret" in
		0 ) TLS_Status="TLS";;
		124 ) TLS_Status="NO_TLS";;
		* ) TLS_Status="CONNFAIL";;
	esac
	conn_estd=0
	while read line; do
		[[ "$line" == "CONNECTION ESTABLISHED" ]] && conn_estd=1
		[[ $conn_estd -ne 1 ]] && continue
		[[ $line != *:* ]] && continue
		key=${line/:*/}
		val=${line/*: /}
		key=${key// /_}
		printf -v "TLS_$key" '%s' "$val"
	done < $tmp
	[[ "$TLS_Verification_error" != "" ]] && TLS_Verification="$TLS_Verification_error"
	jsonreport
}

main()
{
	while read line; do
		[[ $line == \#* ]] && continue
		echo "checking [$line]..."
		scantls $line
	done < $infile
	jsontrailer
}

# Processing starts here
parse_cmdargs "$@"
main