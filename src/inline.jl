module IPythonDisplay

using IJulia
import IJulia: send_ipython, publish, msg_pub, execute_msg, display_dict, displayqueue, undisplay

using Multimedia
import Multimedia: display, redisplay
export display, redisplay, InlineDisplay, undisplay

immutable InlineDisplay <: Display end

# supported MIME types for inline display in IPython, in descending order
# of preference (descending "richness")
const ipy_mime = [ "text/html", "text/latex", "image/svg+xml", "image/png", "image/jpeg", "text/plain" ]

for mime in ipy_mime
    @eval begin
        function display(d::InlineDisplay, ::@MIME($mime), x)
            send_ipython(publish, 
                         msg_pub(execute_msg, "display_data",
                                 ["source" => "julia", # optional
                                  "metadata" => Dict(), # optional
                                  "data" => [$mime => mime_string_repr(MIME($mime), x)] ]))
        end
    end
end

# override display to send IPython a dictionary of all supported
# output types, so that IPython can choose what to display.
function display(d::InlineDisplay, x)
    undisplay(x) # dequeue previous redisplay(x)
    send_ipython(publish, 
                 msg_pub(execute_msg, "display_data",
                         ["source" => "julia", # optional
                          "metadata" => Dict(), # optional
                          "data" => display_dict(x) ]))
end

# we overload redisplay(d, x) to add x to a queue of objects to display,
# with the actual display occuring when display() is called or when
# an input cell has finished executing.

function redisplay(d::InlineDisplay, x)
    if !contains(displayqueue, x)
        push!(displayqueue, x)
    end
end

function display()
    q = copy(displayqueue)
    empty!(displayqueue) # so that undisplay in display(x) is no-op
    for x in q
        display(x)
    end
end

end # module
