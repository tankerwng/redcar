module Redcar
  class REPL
    class ReplMirror
      attr_reader :history, :command_history,
              :command_index, :current_offset,
              :last_output

      # A ReplMirror is a type of Document::Mirror
      include Redcar::Document::Mirror

      def initialize
        @history = initial_preamble
        @mutex = Mutex.new
        initialize_command_history
      end

      def initialize_command_history
        @command_history = REPL.storage['command_history'][title] || []
        @command_history_buffer_size = REPL.storage['command_history_buffer_size']
        @command_index = @command_history.size
        set_current_offset
      end

      # What to display when the REPL is opened. Defaults to the title followed
      # by a prompt
      #
      # @return [String]
      def initial_preamble
        "# #{title}\n# type 'help' for help\n\n#{prompt} "
      end

      # What to display when the help command is run
      #
      # @return [String]
      def help
        help = "Hello! I am a #{title}. I am here to assist you in exploring language APIs.\n\nCommands:\n"
        special_commands.each do |cmd,description|
          help << "#{cmd} : #{description}\n"
        end
        help
      end

      # The special commands supported by the REPL outside of the
      # standard REPL syntax. Each entry is a command and description.
      #
      # @return [Hash]
      def special_commands
        {
          'clear'        => 'Clear command output',
          'reset'        => 'Reset REPL to initial state and clear all command history',
          'help'         => 'Display the help dialog',
          'buffer'       => 'Displays command history buffer size',
          'buffer [int]' => 'Sets command history buffer size'
        }
      end

      # The name of the textmate grammar to apply to the repl history.
      #
      # @return [String]
      def grammar_name
        raise "implement the grammar_name method on your REPL"
      end

      # The prompt to display when the REPL is ready to accept input.
      # Default: ">>"
      #
      # @return [String]
      def prompt
        ">>"
      end

      # The tab title and preamble to display
      # Default: "REPL"
      #
      # @return [String]
      def title
        "REPL"
      end

      # This returns an object that implements:
      #   execute(str:String): String
      def evaluator
        raise "implement evaluator on your REPL"
      end

      # Format the language specific exception to be displayed in the Repl
      #
      # @param [Exception]
      # @return [String]
      def format_error(exception)
        raise "implement format_error on your REPL"
      end

      # Execute a new statement. Accepts the entire pretty formatted history,
      # within which it looks for the last statement and executes it.
      #
      # Do not override
      #
      # @param [String] a string with at least one prompt and statement in it
      def commit(contents)
        command = entered_expression(contents)
        evaluate(command)
      end

      # What did the user just enter?
      #
      # @return [String]
      def entered_expression(contents)
        if contents.split("\n").last =~ /#{prompt}\s+$/
          ""
        else
          last = contents.split(prompt).last
          if last
            last.strip
          else
            ""
          end
        end
      end

      # How many commands will be stored in command history
      #
      # @return [Integer]
      def command_history_buffer_size
        @command_history_buffer_size
      end

      def command_history_buffer_size=(size)
        @command_history_buffer_size = size
        REPL.storage['command_history_buffer_size'] = size
      end

      # The previous command to the command currently displayed,
      # or the last one executed, if none.
      #
      # @return [String]
      def previous_command
        if current = @command_index
          if @command_history.size > 0 and current > 0
            @command_index = current - 1
            command = @command_history[@command_index]
          end
        end
        command
      end

      # The next command to the command currently displayed,
      # or blank, if none.
      #
      # @return [String]
      def next_command
        if @command_index and @command_history.size > @command_index + 1
          @command_index = @command_index + 1
          command = @command_history[@command_index]
        else
          @command_index = @command_history.size
        end
        command
      end

      # Evaluate an expression. Calls execute on the return value of evaluator
      def evaluate(expr)
        add_command(expr)
        if special_commands[expr] or expr =~ /^buffer (\d+)$/
          evaluate_special_command(expr)
        else
          begin
            @last_output = evaluator.execute(expr)
            @history += "=> " + @last_output
          rescue Object => e
            @history += "x> " + format_error(e)
          end
          @history += "\n" + prompt + " "
          set_current_offset
          notify_listeners(:change)
        end
      end

      # Evaluate a special REPL command
      def evaluate_special_command(expr)
        if expr == 'clear'
          clear_history
        elsif expr == 'help'
          append_to_history help
        elsif expr == 'reset'
          reset_history
        elsif expr == 'buffer'
          append_to_history "Current buffer size is #{command_history_buffer_size}"
        elsif expr =~ /^buffer (\d+)$/
          command_history_buffer_size = $1.to_i
          append_to_history "Buffer size set to #{command_history_buffer_size}"
        else
          raise "Special REPL Command not found: #{expr}"
        end
      end

      # Get the complete history as a pretty formatted string.
      #
      # @return [String]
      def read
        @history
      end

      def append_to_history(text)
        @history += "=> " + text
        @history += "\n" + prompt + " "
        set_current_offset
        notify_listeners(:change)
      end

      def clear_history
        @history = prompt + " "
        set_current_offset
        notify_listeners(:change)
      end

      def reset_history
        @history = initial_preamble
        history = REPL.storage['command_history']
        history[title] = []
        REPL.storage['command_history'] = history
        initialize_command_history
        notify_listeners(:change)
      end

      # REPLs always exist because there is no external resource to represent.
      # Therefore, this returns true.
      def exists?
        true
      end

      # REPLs never change except for after commit operations.
      def changed?
        false
      end

      # Appends a command to history
      def add_command(expr)
        @history += expr + "\n"
        @command_history.push expr
        size = @command_history.size
        buffer_size = @command_history_buffer_size
        @command_history.shift(size - buffer_size) if size > buffer_size
        @command_index = @command_history.size
      end

      # Set the position at which a command can begin
      def set_current_offset
        @current_offset = @history.split(//).length
      end
    end
  end
end