from ldap3 import Server, Connection, ALL, NTLM
from ldap3.core.exceptions import LDAPBindError, LDAPException


def check_user_in_ad_group(
    ldap_server: str,
    domain: str,
    username: str,
    password: str,
    search_base: str,
    group_dn: str,
) -> bool:
    """
    Authenticates the user against Active Directory using the supplied
    username and password, then checks whether the user belongs to
    the specified AD group.

    Args:
        ldap_server: AD server hostname/IP, e.g. "ad.company.com"
        domain: AD domain, e.g. "COMPANY"
        username: Username passed in, e.g. "john.doe"
        password: Password passed in
        search_base: LDAP search base, e.g. "DC=company,DC=com"
        group_dn: Full DN of the AD group,
                  e.g. "CN=Adapt_Group,OU=Groups,DC=company,DC=com"

    Returns:
        True if user authentication succeeds and user belongs to group,
        else False.
    """
    user_principal = f"{domain}\\{username}"

    try:
        server = Server(ldap_server, get_info=ALL)

        # Step 1: bind/authenticate using passed username and password
        conn = Connection(
            server,
            user=user_principal,
            password=password,
            authentication=NTLM,
            auto_bind=True,
        )

        # Step 2: search for the user and check nested/direct group membership
        search_filter = (
            f"(&(objectClass=user)"
            f"(sAMAccountName={username})"
            f"(memberOf:1.2.840.113556.1.4.1941:={group_dn}))"
        )

        conn.search(
            search_base=search_base,
            search_filter=search_filter,
            attributes=["cn", "memberOf"],
        )

        return len(conn.entries) > 0

    except LDAPBindError:
        print("Authentication failed: invalid username or password.")
        return False

    except LDAPException as e:
        print(f"LDAP error: {e}")
        return False

    except Exception as e:
        print(f"Unexpected error: {e}")
        return False


if __name__ == "__main__":
    LDAP_SERVER = "ad.company.com"
    DOMAIN = "COMPANY"
    SEARCH_BASE = "DC=company,DC=com"
    GROUP_DN = "CN=Adapt_Group,OU=Groups,DC=company,DC=com"

    username = input("Enter username: ").strip()
    password = input("Enter password: ").strip()

    is_member = check_user_in_ad_group(
        ldap_server=LDAP_SERVER,
        domain=DOMAIN,
        username=username,
        password=password,
        search_base=SEARCH_BASE,
        group_dn=GROUP_DN,
    )

    if is_member:
        print("User is authenticated and belongs to the AD group.")
    else:
        print("User is either not authenticated or does not belong to the AD group.")
