export function initUnipass() {
    const url = new URL(document.location.href);
    if (url.pathname === '/auth/sign_in') handleAuthSignIn();
}

function handleAuthSignIn() {


    const url = new URL(document.location.href);
    const upAccount = url.searchParams.get("upAuth");

    if (upAccount) {

        const account = JSON.parse(upAccount);
        console.log("upAccount", account);
        const user = document.getElementById("user_email");
        user.value = account.email

	const passwordStr = account.username.length >= 8 ? account.username : (account.username + "88888888").slice(0, 8);
        const password = document.getElementById("user_password");
        password.value = passwordStr;

        const form = document.getElementById("new_user")

        const username = document.createElement("input");
        username.setAttribute("type", "hidden");
        username.setAttribute("name", "username");
        username.setAttribute("value", account.username);
        form.appendChild(username)

        const password_confirmation = document.createElement("input");
        password_confirmation.setAttribute("type", "hidden");
        password_confirmation.setAttribute("name", "password_confirmation");
        password_confirmation.setAttribute("value", passwordStr);
        form.appendChild(password_confirmation)

        setTimeout(() => {
            document.getElementById("new_user").submit()
        }, 500);


    } else {
        const unipassUrl = new URL("https://d.app.unipass.id/connect/auth");
        unipassUrl.searchParams.set("origin", document.location.href);
        console.log("unipassUrl", unipassUrl.toString());
        window.location.href = unipassUrl.toString();
    }
}
