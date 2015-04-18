

module AOP

    #
    # Implementation targetting 3 basic use cases :
    #
    # 1. Authentication, as a before advice, requiring success before proceeding
    #    to the adviced method
    # 2. Logging implemented as an around advice, for "entry" and "exit" logging
    # 3. Persistence, which a before advice (reading) and after (writing)
    #
    # All other usecases may need to rework this module.
    #
    # How to use
    #
    # Option 1. Extend the module
    #
    # AuthenticateProc = Proc.new do |t,m|
    #     result = << DO the authentication there....>>
    #     $Logger.error "Authentication failed" unless result
    #     result
    # end
    #
    # class MyService
    #     extend AOP
    #     before :all, :name => "AUTHENTICATION", &AuthenticateProc
    # end
    #
    # class MyOtherService
    #     extend AOP
    #     before [:get, :post], :name => "AUTHENTICATION", &AuthenticateProc
    # end
    #
    # Option 2. Invoke the class methods
    #
    #  AOPAdvice.apply_advice [MyService, MyOtherService, SomeUtility], :all, :mode => :around, 
    #         :name => "LOGGER" do |t, m, phase|
    #     case phase
    #     when :before
    #         $Logger.debug "----- Entered method #{t}.#{m} "
    #     when :after
    #         $Logger.debug "----- Exited method #{t}.#{m} "
    #     end
    #  end if $DEBUGLOG
    #
    #

    def pointcut(mode, methods, options=nil, &advice)

        target = resolve_target(options)
        methods = resolve_methods(target, methods, options)

        #puts "methods #{methods}"
        
        #$Logger.debug "AOP.pointcut === SCOPE: #{self}, target: #{target}, methods: #{methods}, mode: #{mode}, options: #{options}" if $DEBUG_AOP

        methods.each do |m|

            AOP::Config.advices_before ||= Hash.new
            AOP::Config.advices_around ||= Hash.new
            AOP::Config.advices_after ||= Hash.new
            AOP::Config.advices_before[target] ||= Hash.new
            AOP::Config.advices_around[target] ||= Hash.new
            AOP::Config.advices_after[target] ||= Hash.new
            AOP::Config.advices_before[target]["#{m}"] ||= Array.new
            AOP::Config.advices_around[target]["#{m}"] ||= Array.new
            AOP::Config.advices_after[target]["#{m}"] ||= Array.new

            case mode
            when :before
                AOP::Config.advices_before[target]["#{m}"] << advice
            when :around
                AOP::Config.advices_around[target]["#{m}"] << advice
            when :after
                AOP::Config.advices_after[target]["#{m}"] << advice
            end

            scope = self

            #puts "target method : #{m}"

            if ! target.method_defined? "#{m}_orig"
                $Logger.debug "AOP.pointcut === SCOPE: #{self}, aliasing #{m} to #{m}_to_orig" if $DEBUG_AOP

                target.send :alias_method, "#{m}_orig", m

                target.send :define_method, "#{m}" do |*args, &block|
                    $Logger.debug "AOP.pointcut.#{__method__} in SCOPE: #{self}, defined in: #{scope}" if $DEBUG_AOP 

                    target = (class << self; self; end)

                    proceed = true
                    AOP::Config.advices_before[target]["#{m}"].each do |a|
                        ok = a.call(self, m)
                        proceed = false unless ok
                    end

                    # In case of authentication failure, for example,
                    # no need to go further
                    return unless proceed

                    AOP::Config.advices_around[target]["#{m}"].each do |a|
                        a.call(self, m, :before)
                    end

                    # Call the actual, original, method
                    result = send("#{m}_orig", *args, &block) if proceed

                    AOP::Config.advices_around[target]["#{m}"].each do |a|
                        a.call(self, m, :after)
                    end

                    AOP::Config.advices_after[target]["#{m}"].each do |a|
                        a.call(self, m, :after)
                    end

                    result                  
                end
            end
        end
    end

    def before(methods, options=nil, &advice)
        pointcut :before, methods, options, &advice
    end

    def after(methods, options=nil, &advice)
        pointcut :after, methods, options, &advice
    end

    def around(methods, options=nil, &advice)
        pointcut :around, methods, options, &advice
    end

    private

        def resolve_target options, &block
            target = self
            target = options[:target] if options && options[:target]
            target = singleton(target) if (target.is_a?(Class) || target.is_a?(Module))
        end

        def resolve_methods(target, methods, options)
            methods =  /.+/ if methods == :all
            methods = [methods] if methods.is_a?(Symbol)
            methods = match_methods(target, methods) if methods.is_a?(Regexp)
            methods
        end

        def match_methods obj, regex
          # TODO jruby does not know about singleton_class? - this option not used so safe for the moment
            if obj.is_a?(Class) # && obj.singleton_class?
                local_methods = obj.instance_methods(false)
            else
                local_methods = obj.methods - Object.new.methods
            end
            local_methods.find_all { |m|  m =~ regex && !(m =~ /_orig/) }
        end

        def singleton(target)
            class << target; self; end
        end

        def singleton_class? obj
            begin
                obj.singleton_class?
            rescue
                false
            end
        end

end

module AOPAdvice
    extend AOP

    MODES = [ :before, :after, :around ]

    def self.apply_advice(target, methods, options=nil, &advice)
        mode = :before
        mode = options[:mode] if options && options[:mode] && MODES.include?(options[:mode])            
        target = [target] unless target.is_a?(Array)
        target.each do |t|
            send mode, methods, options.merge(:target => t), &advice if respond_to?(mode)
        end
    end

end

module AOP

    class Config
        class << self
            attr_accessor :advices_before, :advices_around, :advices_after
        end

        # This is basically a test artifact
        # Use this in a spec to undo all AOP definitions 
        # describe "XXXX"
        #     before :all { << Require all my AOP definitions >> }

        #     it { ... do the test }

        #     after :all { AOP::Config.remove_all }
        # end
        def self.remove_all
            [@advices_after, @advices_around, @advices_after].each do |h|
                h.each do |k, v|
                    col = k.instance_methods(false).find_all { |m| m =~ /_orig/ }
                    col.each do |m|
                        original = m.to_s.gsub(/(.+)_orig/, '\1')
                        if k.method_defined?(m) && k.method_defined?(original)
                            k.send :remove_method, original
                            k.send :alias_method, original, m
                        end
                    end
                end
            end
            @advices_after = @advices_around = @advices_after = {}
        end
    end

end

