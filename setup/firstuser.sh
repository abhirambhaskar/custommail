#!/bin/bash

# If there aren't any mail users yet, create one.
if [ -z "$(management/cli.py user)" ]; then
    # The output of "management/cli.py user" is a list of mail users. If there
    # aren't any yet, it'll be empty.

    # If we didn't ask for an email address at the start, do so now.
    if [ -z "${EMAIL_ADDR:-}" ]; then
        # In an interactive shell, ask the user for an email address.
        if [ -z "${NONINTERACTIVE:-}" ]; then
            echo "Let's create your first mail account."
            echo -n "What email address do you want? [me@$(get_default_hostname)]: "
            read EMAIL_ADDR
            EMAIL_ADDR=${EMAIL_ADDR:-me@$(get_default_hostname)}

            if [ -z "$EMAIL_ADDR" ]; then
                # User provided empty input
                exit
            fi
            while ! management/mailconfig.py validate-email "$EMAIL_ADDR"
            do
                echo "That's not a valid email address."
                echo -n "What email address do you want? [$EMAIL_ADDR]: "
                read EMAIL_ADDR
                EMAIL_ADDR=${EMAIL_ADDR:-$EMAIL_ADDR}
                if [ -z "$EMAIL_ADDR" ]; then
                    # User provided empty input
                    exit
                fi
            done

        # But in a non-interactive shell, just make something up.
        # This is normally for testing.
        else
            # Use me@PRIMARY_HOSTNAME
            EMAIL_ADDR=me@$PRIMARY_HOSTNAME
            EMAIL_PW=trDBkyv1JQ7SB6hZ1VKUDY2XJaRE9R3Opi360HM7naeQ9fO3hJ
            echo
            echo "Creating a new administrative mail account for $EMAIL_ADDR with password $EMAIL_PW."
            echo
        fi
    else
        echo
        echo "Okay. I'm about to set up $EMAIL_ADDR for you. This account will also"
        echo "have access to the box's control panel."
    fi

    # Create the user's mail account. This will ask for a password if none was given above.
    management/cli.py user add $EMAIL_ADDR ${EMAIL_PW:-}

    # Make it an admin.
    hide_output management/cli.py user make-admin $EMAIL_ADDR

    # Create an alias to which we'll direct all automatically-created administrative aliases.
    hide_output management/cli.py alias add administrator@$PRIMARY_HOSTNAME $EMAIL_ADDR > /dev/null
fi
