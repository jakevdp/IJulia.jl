module Multimedia

export Display, display, pushdisplay, popdisplay, displayable, redisplay,
   MIME, @MIME, writemime, reprmime, stringmime, istext,
   mimewritable, TextDisplay, reinit_displays

###########################################################################
# We define a singleton type MIME{mime symbol} for each MIME type, so
# that Julia's dispatch and overloading mechanisms can be used to
# dispatch writemime and to add conversions for new types.

immutable MIME{mime} end

import Base: show, string, convert
MIME(s) = MIME{symbol(s)}()
show{mime}(io::IO, ::MIME{mime}) = print(io, "MIME type ", string(mime))
string{mime}(::MIME{mime}) = string(mime)

# needs to be a macro so that we can use ::@mime(s) in type declarations
macro MIME(s)
    quote
        MIME{symbol($s)}
    end
end

###########################################################################
# For any type T one can define writemime(io, ::@MIME(mime), x::T) = ...
# in order to provide a way to export T as a given mime type.

# We provide a fallback text/plain representation of any type:
writemime(io, ::@MIME("text/plain"), x) = repl_show(io, x)

mimewritable{mime}(::MIME{mime}, T::Type) =
  method_exists(writemime, (IO, MIME{mime}, T))

# it is convenient to accept strings instead of ::MIME
writemime(io, m::String, x) = writemime(io, MIME(m), x)
mimewritable(m::String, T::Type) = mimewritable(MIME(m), T)

###########################################################################
# MIME types are assumed to be binary data except for a set of types known
# to be text data (possibly Unicode).  istext(m) returns whether
# m::MIME is text data, and reprmime(m, x) returns x written to either
# a string (for text m::MIME) or a Vector{Uint8} (for binary m::MIME),
# assuming the corresponding write_mime method exists.  stringmime
# is like reprmime except that it always returns a string, which in the
# case of binary data is Base64-encoded.
#
# Also, if reprmime is passed a String for a text type or Vector{Uint8} for
# a binary type, the argument is assumed to already be in the corresponding
# format and is returned unmodified.  This is useful so that raw data can be
# passed to display(m::MIME, x).

for mime in ["text/cmd", "text/css", "text/csv", "text/html", "text/javascript", "text/plain", "text/vcard", "text/xml", "application/atom+xml", "application/ecmascript", "application/json", "application/rdf+xml", "application/rss+xml", "application/xml-dtd", "application/postscript", "image/svg+xml", "application/x-latex", "application/xhtml+xml", "application/javascript", "application/xml", "model/x3d+xml", "model/x3d+vrml", "model/vrml"]
    @eval begin
        istext(::@MIME($mime)) = true
        reprmime(m::@MIME($mime), x::String) = x
        reprmime(m::@MIME($mime), x) = sprint(writemime, m, x)
        stringmime(m::@MIME($mime), x) = reprmime(m, x)
        # avoid method ambiguities with definitions below:
        # (Q: should we treat Vector{Uint8} as a bytestring?)
        reprmime(m::@MIME($mime), x::Vector{Uint8}) = sprint(writemime, m, x)
        stringmime(m::@MIME($mime), x::Vector{Uint8}) = reprmime(m, x)
    end
end

istext(::MIME) = false
function reprmime(m::MIME, x)
    s = IOBuffer()
    writemime(s, m, x)
    takebuf_array(s)
end
reprmime(m::MIME, x::Vector{Uint8}) = x
using Base64
stringmime(m::MIME, x) = base64(writemime, m, x)
stringmime(m::MIME, x::Vector{Uint8}) = base64(write, x)

# it is convenient to accept strings instead of ::MIME
istext(m::String) = istext(MIME(m))
reprmime(m::String, x) = reprmime(MIME(m), x)
stringmime(m::String, x) = stringmime(MIME(m), x)

###########################################################################
# We have an abstract Display class that can be subclassed in order to
# define new rich-display output devices.  A typical subclass should
# overload display(d::Display, m::MIME, x) for supported MIME types m,
# (typically using reprmime or stringmime to get the MIME
# representation of x) and should also overload display(d::Display, x)
# to display x in whatever MIME type is preferred by the Display and
# is writable by x.  display(..., x) should throw a MethodError if x
# cannot be displayed.  The return value of display(...) is up to the
# Display type.

abstract Display

# it is convenient to accept strings instead of ::MIME
display(d::Display, mime::String, x) = display(d, MIME(mime), x)
display(mime::String, x) = display(MIME(mime), x)
displayable(d::Display, mime::String) = displayable(d, MIME(mime))
displayable(mime::String) = displayable(MIME(mime))

# simplest display, which only knows how to display text/plain
immutable TextDisplay <: Display
    io::IO
end
display(d::TextDisplay, ::@MIME("text/plain"), x) =
    writemime(d.io, MIME("text/plain"), x)
display(d::TextDisplay, x) = display(d, MIME("text/plain"), x)

import Base: close, flush
flush(d::TextDisplay) = flush(d.io)
close(d::TextDisplay) = close(d.io)

###########################################################################
# We keep a stack of Displays, and calling display(x) uses the topmost
# Display that is capable of displaying x (doesn't throw an error)

const displays = Display[]
function pushdisplay(d::Display)
    global displays
    push!(displays, d)
end
popdisplay() = pop!(displays)
function popdisplay(d::Display)
    for i = length(displays):-1:1
        if d == displays[i]
            return splice!(displays, i)
        end
    end
    throw(KeyError(d))
end
function reinit_displays()
    empty!(displays)
    pushdisplay(TextDisplay(STDOUT))
end

function display(x)
    for i = length(displays):-1:1
        try
            return display(displays[i], x)
        catch e
            if !isa(e, MethodError)
                rethrow()
            end
        end
    end
    throw(MethodError(display, (x,)))
end

function display(m::MIME, x)
    for i = length(displays):-1:1
        try
            return display(displays[i], m, x)
        catch e
            if !isa(e, MethodError)
                rethrow()
            end
        end
    end
    throw(MethodError(display, (m, x)))
end

displayable{D<:Display,mime}(d::D, ::MIME{mime}) =
  method_exists(display, (D, MIME{mime}, Any))

function displayable(m::MIME)
    for d in displays
        if displayable(d, m)
            return true
        end
    end
    return false
end

###########################################################################
# The redisplay method can be overridden by a Display in order to
# update an existing display (instead of, for example, opening a new
# window), and is used by the IJulia interface to defer display
# until the next interactive prompt.  This is especially useful
# for Matlab/Pylab-like stateful plotting interfaces, where
# a plot is created and then modified many times (xlabel, title, etc.).

function redisplay(x)
    for i = length(displays):-1:1
        try
            return redisplay(displays[i], x)
        catch e
            if !isa(e, MethodError)
                rethrow()
            end
        end
    end
    throw(MethodError(redisplay, (x,)))
end

function redisplay(m::Union(MIME,String), x)
    for i = length(displays):-1:1
        try
            return redisplay(displays[i], m, x)
        catch e
            if !isa(e, MethodError)
                rethrow()
            end
        end
    end
    throw(MethodError(redisplay, (m, x)))
end

# default redisplay is simply to call display
redisplay(d::Display, x) = display(d, x)
redisplay(d::Display, m::Union(MIME,String), x) = display(d, m, x)

###########################################################################

end # module
