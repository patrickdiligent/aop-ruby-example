#
# Example usage
#

ENTRY_EXIT_LOGGER = $Logger.module_logger('method_entry_exit')

AOPAdvice.apply_advice [Meetup::Groups, Meetup::Authorize, Meetup::Request], :all, :mode => :around, :name => "LOGGER" do |t, m, phase|
    case phase
    when :before
        ENTRY_EXIT_LOGGER.debug "----- Entered method #{t}.#{m} "
    when :after
        ENTRY_EXIT_LOGGER.debug "----- Exited method #{t}.#{m} "
    end
end if $DEBUGLOG
