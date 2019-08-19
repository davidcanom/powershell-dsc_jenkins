import jenkins.model.*
import hudson.security.*
import org.jenkinsci.main.modules.cli.auth.ssh.UserPropertyImpl

def jenkins_security_realm = 'jenkins'
def jenkins_username = '_jenkinsusername_'
def jenkins_password = '_jenkinspassword_'

def jenkins = Jenkins.getInstance()

if (jenkins_security_realm == 'jenkins') {
    if (!(jenkins.getSecurityRealm() instanceof HudsonPrivateSecurityRealm)) {
        jenkins.setSecurityRealm(new HudsonPrivateSecurityRealm(false))
    }

	if (!(jenkins.getAuthorizationStrategy() instanceof FullControlOnceLoggedInAuthorizationStrategy)) {
        jenkins.setAuthorizationStrategy(new FullControlOnceLoggedInAuthorizationStrategy())
    }

    def currentUsers = jenkins.getSecurityRealm().getAllUsers().collect { it.getId() }

    if (!(jenkins_username in currentUsers)) {
        def user = jenkins.getSecurityRealm().createAccount(jenkins_username, jenkins_password)
        user.save()
    }
} else if (jenkins_security_realm == 'none') {
    // If we leave the user, further attempts to use jenkins-cli.jar with
    // key-based authentication enabled fail for some reason. Clearing the
    // user's SSH key wasn't enough to solve the problem.
    jenkins_user = jenkins.getUser(jenkins_username)
    if (jenkins_user) {
        jenkins_user.delete()
    }
    jenkins.disableSecurity()
}
jenkins.save()