if [ -z "${NONINTERACTIVE:-}" ]; then
    # Check for necessary files and install missing packages
    if [ ! -f /usr/bin/dialog ] || [ ! -f /usr/bin/python3 ] || [ ! -f /usr/bin/pip3 ]; then
        echo "Installing packages needed for setup..."
        apt-get -q -q update
        apt-get -q -q install dialog python3 python3-pip || exit 1
    fi

    # Install the email_validator globally if not in a virtualenv
    hide_output pip3 install "email_validator>=1.0.0" || exit 1

    # Replace the message_box with echo commands
    echo "Mail-in-a-Box Installation"
    echo "Hello and thanks for deploying a Mail-in-a-Box!"
    echo -e "\nI'm going to ask you a few questions."
    echo -e "\nTo change your answers later, just run 'sudo mailinabox' from the command line."
    echo -e "\nNOTE: You should only install this on a brand new Ubuntu installation 100% dedicated to Mail-in-a-Box."
    echo "Mail-in-a-Box will, for example, remove apache2."
fi


# The box needs a name.
if [ -z "${PRIMARY_HOSTNAME:-}" ]; then
	if [ -z "${DEFAULT_PRIMARY_HOSTNAME:-}" ]; then
		# We recommend to use box.example.com as this hosts name. The
		# domain the user possibly wants to use is example.com then.
		# We strip the string "box." from the hostname to get the mail
		# domain. If the hostname differs, nothing happens here.
		DEFAULT_DOMAIN_GUESS=$(echo $(get_default_hostname) | sed -e 's/^box\.//')

		# This is the first run. Ask the user for his email address so we can
		# provide the best default for the box's hostname.
		echo -e "What email address are you setting this box up to manage?\n"
		echo -e "The part after the @-sign must be a domain name or subdomain that you control."
		echo -e "You can add other email addresses to this box later (including email addresses on other domain names or subdomains you control).\n"
		echo -n "Please enter your email address [me@$DEFAULT_DOMAIN_GUESS]: "
		read EMAIL_ADDR

		if [ -z "$EMAIL_ADDR" ]; then
			echo "Email address is required. Exiting."
			exit 1
		fi

		while ! python3 management/mailconfig.py validate-email "$EMAIL_ADDR"; do
			echo -n "That's not a valid email address. Please enter a valid email address: "
			read EMAIL_ADDR
			if [ -z "$EMAIL_ADDR" ]; then
				echo "Email address is required. Exiting."
				exit 1
			fi
		done

		# Take the part after the @-sign as the user's domain name, and add
		# 'box.' to the beginning to create a default hostname for this machine.
		DEFAULT_PRIMARY_HOSTNAME=webmail.$(echo $EMAIL_ADDR | sed 's/.*@//')
	fi

	# Print instructions for the user
	echo "This box needs a name, called a 'hostname'. The name will form a part of the box's web address."
	echo -e "\nWe recommend that the name be a subdomain of the domain in your email address, so we're suggesting $DEFAULT_PRIMARY_HOSTNAME."
	echo -e "\nYou can change it, but we recommend you don't."

	# Prompt the user for the hostname, suggesting the default
	echo -n "Please enter the hostname [$DEFAULT_PRIMARY_HOSTNAME]: "
	read PRIMARY_HOSTNAME

	# Use the default if the user input was empty
	if [ -z "$PRIMARY_HOSTNAME" ]; then
		PRIMARY_HOSTNAME=$DEFAULT_PRIMARY_HOSTNAME
	fi

	# Check if the PRIMARY_HOSTNAME was eventually set or not
	if [ -z "$PRIMARY_HOSTNAME" ]; then
		echo "Hostname is required. Exiting."
		exit 1
	fi

fi

# If the machine is behind a NAT, inside a VM, etc., it may not know
# its IP address on the public network / the Internet. Ask the Internet
# and possibly confirm with user.
if [ -z "${PUBLIC_IP:-}" ]; then
	# Ask the Internet.
	GUESSED_IP=$(get_publicip_from_web_service 4)

	# On the first run, if we got an answer from the Internet then don't
	# ask the user.
	if [[ -z "${DEFAULT_PUBLIC_IP:-}" && ! -z "$GUESSED_IP" ]]; then
		PUBLIC_IP=$GUESSED_IP

	# Otherwise on the first run at least provide a default.
	elif [[ -z "${DEFAULT_PUBLIC_IP:-}" ]]; then
		DEFAULT_PUBLIC_IP=$(get_default_privateip 4)

	# On later runs, if the previous value matches the guessed value then
	# don't ask the user either.
	elif [ "${DEFAULT_PUBLIC_IP:-}" == "$GUESSED_IP" ]; then
		PUBLIC_IP=$GUESSED_IP
	fi

	if [ -z "${PUBLIC_IP:-}" ]; then
		input_box "Public IP Address" \
			"Enter the public IP address of this machine, as given to you by your ISP.
			\n\nPublic IP address:" \
			${DEFAULT_PUBLIC_IP:-} \
			PUBLIC_IP

		if [ -z "$PUBLIC_IP" ]; then
			# user hit ESC/cancel
			exit
		fi
	fi
fi

# Same for IPv6. But it's optional. Also, if it looks like the system
# doesn't have an IPv6, don't ask for one.
if [ -z "${PUBLIC_IPV6:-}" ]; then
	# Ask the Internet.
	GUESSED_IP=$(get_publicip_from_web_service 6)
	MATCHED=0
	if [[ -z "${DEFAULT_PUBLIC_IPV6:-}" && ! -z "$GUESSED_IP" ]]; then
		PUBLIC_IPV6=$GUESSED_IP
	elif [[ "${DEFAULT_PUBLIC_IPV6:-}" == "$GUESSED_IP" ]]; then
		# No IPv6 entered and machine seems to have none, or what
		# the user entered matches what the Internet tells us.
		PUBLIC_IPV6=$GUESSED_IP
		MATCHED=1
	elif [[ -z "${DEFAULT_PUBLIC_IPV6:-}" ]]; then
		DEFAULT_PUBLIC_IP=$(get_default_privateip 6)
	fi

	if [[ -z "${PUBLIC_IPV6:-}" && $MATCHED == 0 ]]; then
		input_box "IPv6 Address (Optional)" \
			"Enter the public IPv6 address of this machine, as given to you by your ISP.
			\n\nLeave blank if the machine does not have an IPv6 address.
			\n\nPublic IPv6 address:" \
			${DEFAULT_PUBLIC_IPV6:-} \
			PUBLIC_IPV6

		if [ ! $PUBLIC_IPV6_EXITCODE ]; then
			# user hit ESC/cancel
			exit
		fi
	fi
fi

# Get the IP addresses of the local network interface(s) that are connected
# to the Internet. We need these when we want to have services bind only to
# the public network interfaces (not loopback, not tunnel interfaces).
if [ -z "${PRIVATE_IP:-}" ]; then
	PRIVATE_IP=$(get_default_privateip 4)
fi
if [ -z "${PRIVATE_IPV6:-}" ]; then
	PRIVATE_IPV6=$(get_default_privateip 6)
fi
if [[ -z "$PRIVATE_IP" && -z "$PRIVATE_IPV6" ]]; then
	echo
	echo "I could not determine the IP or IPv6 address of the network inteface"
	echo "for connecting to the Internet. Setup must stop."
	echo
	hostname -I
	route
	echo
	exit
fi

# Automatic configuration, e.g. as used in our Vagrant configuration.
if [ "$PUBLIC_IP" = "auto" ]; then
	# Use a public API to get our public IP address, or fall back to local network configuration.
	PUBLIC_IP=$(get_publicip_from_web_service 4 || get_default_privateip 4)
fi
if [ "$PUBLIC_IPV6" = "auto" ]; then
	# Use a public API to get our public IPv6 address, or fall back to local network configuration.
	PUBLIC_IPV6=$(get_publicip_from_web_service 6 || get_default_privateip 6)
fi
if [ "$PRIMARY_HOSTNAME" = "auto" ]; then
	PRIMARY_HOSTNAME=$(get_default_hostname)
fi

# Set STORAGE_USER and STORAGE_ROOT to default values (user-data and /home/user-data), unless
# we've already got those values from a previous run.
if [ -z "${STORAGE_USER:-}" ]; then
	STORAGE_USER=$([[ -z "${DEFAULT_STORAGE_USER:-}" ]] && echo "user-data" || echo "$DEFAULT_STORAGE_USER")
fi
if [ -z "${STORAGE_ROOT:-}" ]; then
	STORAGE_ROOT=$([[ -z "${DEFAULT_STORAGE_ROOT:-}" ]] && echo "/home/$STORAGE_USER" || echo "$DEFAULT_STORAGE_ROOT")
fi

# Show the configuration, since the user may have not entered it manually.
echo
echo "Primary Hostname: $PRIMARY_HOSTNAME"
echo "Public IP Address: $PUBLIC_IP"
if [ ! -z "$PUBLIC_IPV6" ]; then
	echo "Public IPv6 Address: $PUBLIC_IPV6"
fi
if [ "$PRIVATE_IP" != "$PUBLIC_IP" ]; then
	echo "Private IP Address: $PRIVATE_IP"
fi
if [ "$PRIVATE_IPV6" != "$PUBLIC_IPV6" ]; then
	echo "Private IPv6 Address: $PRIVATE_IPV6"
fi
if [ -f /usr/bin/git ] && [ -d .git ]; then
	echo "Mail-in-a-Box Version: " $(git describe --always)
fi
echo
