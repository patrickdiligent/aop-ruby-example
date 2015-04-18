
#
# Example Usage
# 

AuthenticateProc = Proc.new do |t,m|
    result = ..... (authenticate to service...) do |cred|
        cred.email = ....
        cred.password = ....
    end           
    $Logger.error "Authentication failed" unless result
    result
end

class Service::Categories
    extend AOP
    before :all, :name => "AUTHENTICATION", &AuthenticateProc
end

class Service::Users
    extend AOP
    before :all, :name => "AUTHENTICATION", &AuthenticateProc
end
