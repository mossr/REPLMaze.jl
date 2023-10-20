module REPLMaze

using Random

export
    play,
    draw,
    loadsprites,
    paint,
    PIX,
    COLORS

global const COLORS = Dict(
    :black => "\e[0;30m",
    :red => "\e[0;31m",
    :green => "\e[0;32m",
    :yellow => "\e[0;33m",
    :blue => "\e[0;34m",
    :purple => "\e[0;35m",
    :cyan => "\e[0;36m",
    :white => "\e[0;37m",
    :orange => "\e[38;5;202m",
    :brown => "\e[38;5;94m",
    :gray => "\e[38;5;249m",
    :darkgray => "\e[38;5;237m",
    :darkred => "\e[38;5;52m",
    :reset => "\e[0m",
)
global PIX = "██"
global BACKGROUND = "$(COLORS[:black])$PIX$(COLORS[:reset])"
global BORDER = "$(COLORS[:darkgray])$PIX$(COLORS[:reset])"

global const KEY_UP = 'w'
global const KEY_LEFT = 'a'
global const KEY_DOWN = 's'
global const KEY_RIGHT = 'd'
global const KEY_RESET = 'r'
global const KEY_PO = 'p'
global const KEY_PO⁻ = '-'
global const KEY_PO⁺ = '='
global const KEY_PO_RESET = 'o'
global const KEY_TICK = '`'

global const SCOREDOT = 10
global const SCORESUPERDOT = 50

global DELAY = 0.033
global TIMEOUT = 0
global MAXTIMEOUT = 120/DELAY
global VELOCITY_STEP = 1
global POSITION = missing
global POSITION′ = missing
global VELOCITY = [0, 0]
global VELOCITY′ = [0, 0]
global PAUSED = false
global RESET = false
global SUBPIXEL = 2
global POWINDOWDEFAULT = [5, 5] # partial observable window
global POWINDOW = copy(POWINDOWDEFAULT) # adjustable partial observable window
global PO = false # toggle partial observablility
hide_cursor() = print("\e[?25l")
show_cursor() = println("\e[?25h")
clearscreen() = println("\33[2J")
paint(pix, color) = "$(color)$(pix)$(COLORS[:reset])"
global AGENT = paint("🔵", COLORS[:blue])
global WALL = paint(PIX, COLORS[:darkgray])
global FINISHEDWALL = paint(PIX, COLORS[:darkred])
global FLAG = paint("🚩", COLORS[:red])
global DIRS = [[0,2], [2,0], [0,-2], [-2,0]]


function play(; w=25, h=25, po=false, agent=AGENT, flag=FLAG)
    global POSITION
    global PAUSED
    global SUBPIXEL
    global PO
    global TIMEOUT
    global MAXTIMEOUT
    global AGENT
    global FLAG

    TIMEOUT = 0
    PAUSED = false
    PO = po

    AGENT = agent
    FLAG = flag

    hide_cursor()
    clearscreen()
    M, POSITION = createmaze(w, h)
    set_keyboard_input_mode()
    task = capture_keyboard_input()

    spc = 0
    subpixelmove = false
    Mfo = deepcopy(M) # fully observable maze

    while !PAUSED && TIMEOUT <= MAXTIMEOUT
        subpixelmove = spc == SUBPIXEL
        if subpixelmove
            spc = 0
        end
        spc += 1

        PAUSED = game!(M; w, h, subpixelmove, Mfo)
        sleep(DELAY)
    end

    close_keyboard_buffer()
    show_cursor()
    try Base.throwto(task, InterruptException()) catch end

    return nothing
end


function game!(M; w=Inf, h=Inf, subpixelmove=false, Mfo=missing)
    global POSITION
    global POSITION′
    global VELOCITY
    global VELOCITY′
    global AGENT
    global PO
    global RESET

    ispaused = keypress!(w, h)

    # apply velocity
    POSITION′ = POSITION + VELOCITY′

    # one-step lookahead given existing position and velocity
    position′′ = POSITION + VELOCITY

    isongoal = false

    if subpixelmove
        if hitwall(M, POSITION′) && !hitwall(M, position′′)
            M[POSITION...] = "  "
            Mfo[POSITION...] = "  "

            POSITION′ = position′′
            POSITION = POSITION′
            
            isongoal = ongoal(M, POSITION) || ongoal(M, POSITION′)

            M[POSITION...] = AGENT
            Mfo[POSITION...] = AGENT
        elseif !hitwall(M, POSITION′)
            M[POSITION...] = "  "
            Mfo[POSITION...] = "  "

            POSITION = POSITION′
            VELOCITY = VELOCITY′
            
            isongoal = ongoal(M, POSITION) || ongoal(M, POSITION′)

            M[POSITION...] = AGENT
            Mfo[POSITION...] = AGENT
        end
    end

    draw(M; isongoal, Mfo)

    # Finished level
    if isongoal || RESET
        if isongoal
            sleep(2)
        else
            RESET = false
        end
        VELOCITY = [0, 0]
        VELOCITY′ = [0, 0]
        M[:], POSITION = createmaze(w, h)
        Mfo[:] = deepcopy(M)
    end

    return ispaused
end


hitwall(M, position) = M[position...] == WALL
ongoal(M, position) = M[position...] == FLAG


function findwindow(M, position)
    global POWINDOW
    poy, pox = POWINDOW

    X = max(1, position[2]-pox):min(size(M,2), position[2]+pox)
    Y = max(1, position[1]-poy):min(size(M,1), position[1]+poy)

    return Y, X # Note: Flipped x-y
end


function draw(M; isongoal=false, Mfo=missing)
    global POWINDOW
    global POSITION
    global PO

    # clearscreen() # Note: this flickers
    if PO
        poY, poX = findwindow(M, POSITION)
        M[:] .= "  "
        M[poY, poX] .= Mfo[poY, poX]
    else
        M[:] = Mfo
    end

    if isongoal
        M[:] = Mfo
        M[M .== WALL] .= FINISHEDWALL
    end
    bio = stdout
    print(bio, "\033[1;1H" * join([join(row) for row in eachrow(M)], "\n"))
    return nothing
end


function createmaze(w, h)
    M = fill(WALL, w, h)
    V = falses(size(M))
    queue = []

    # https://www.algosome.com/articles/maze-generation-depth-first.html

    # 1) Randomly select a node (or cell) 𝐍
    px, py = [1, 1]
    N = [py, px]
    stop = false
    initN = N

    while !stop
        # 2) Push the node 𝐍 onto a queue 𝐐
        push!(queue, N)

        # 3) Mark the cell 𝐍 as visited.
        M[N...] = "  "
        V[N...] = true

        while true
            # 4) Randomly select an adjacent cell 𝐀 of node 𝐍 that has not been visited.
            A = missing
            for neighbor in shuffle(neighbors(M, N...))
                if !V[neighbor...]
                    A = neighbor
                    break
                end
            end

            # 4a) If all the neighbors of 𝐍 have been visited:
            if ismissing(A)
                # - Continue to pop the queue 𝐐 until a node is encounted with at least one non-visted neighbor — assign this node to 𝐍 and go to step 4.
                encountered = false
                while !isempty(queue)
                    N′ = popfirst!(queue)
                    if any(neighbor->V[neighbor...], neighbors(M, N′...))
                        N = N′
                        encountered = true
                        break
                    end
                end
                # - If no nodes exist: stop.
                if !encountered
                    stop = true
                    break
                end
            else
                # 5) Break the wall between 𝐍 and 𝐀
                M[N + ((A - N) .÷ 2)...] = "  "

                # 6) Assign the value 𝐀 to 𝐍
                N = A

                # 7) Go to step 2.
                break
            end
        end
    end
    M = finalize(M, V, initN)
    position = initN + [1,1]
    return M, position
end


function neighbors(M, px, py)
    N = []
    for d in DIRS
        dx, dy = d
        px′, py′ = px + dx, py + dy
        if checkbounds(Bool, M, px′, py′)
            push!(N, [px′, py′])
        end
    end
    return N
end


function finalize(M, V, initN; bordergoal=false)
    global FLAG
    global AGENT
    M[initN...] = AGENT

    if bordergoal
        goal = rand(filter(p->p.I[1] == 1 || p.I[1] == axes(V,1)[end] || p.I[end] == 1 || p.I[end] == axes(V,2)[end] || p.I != initN, findall(V))).I
    else
        goal = rand(filter(p->p.I != initN, findall(V))).I
    end

    # Add border
    M = addborder(M)

    goal′ = goal .+ [1,1]
    if bordergoal
        if goal[1] == 1
            gd = [-1,0]
        elseif goal[1] == axes(V,1)[end]
            gd = [1,0]
        elseif goal[2] == 1
            gd = [0,-1]
        elseif goal[2] == axes(V,2)[end]
            gd = [0,1]
        end
        M[goal′ .+ gd...] = FLAG
    else
        M[goal′...] = FLAG
    end

    return M
end


function addborder(M)
    M′ = fill(WALL, size(M) .+ 2)
    M′[2:end-1, 2:end-1] = M
    return M′
end


function set_keyboard_input_mode()
    ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid}, Int32), stdin.handle, true)
end


# Key input handling
global BUFFER
function capture_keyboard_input()
    global BUFFER, PAUSED
    BUFFER = Channel{Char}(100)

    return @async while !PAUSED
        put!(BUFFER, read(stdin, Char))
    end
end


function close_keyboard_buffer()
    ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid}, Int32), stdin.handle, false)
end


function readinput()
    if isready(BUFFER)
        return take!(BUFFER)
    end
    return nothing
end


function keypress!(w, h)
    global TIMEOUT
    global VELOCITY_STEP
    global VELOCITY′
    global POWINDOW
    global POWINDOWDEFAULT
    global PO
    global RESET

    key = readinput()

    if key == KEY_LEFT
        VELOCITY′ = [0, -VELOCITY_STEP]
    elseif key == KEY_RIGHT
        VELOCITY′ = [0, VELOCITY_STEP]
    elseif key == KEY_UP
        VELOCITY′ = [-VELOCITY_STEP, 0]
    elseif key == KEY_DOWN
        VELOCITY′ = [VELOCITY_STEP, 0]
    elseif key == KEY_PO
        PO = !PO # partial observablility
    elseif key == KEY_PO⁻
        POWINDOW = max.(POWINDOW .- 1, [1,1])
    elseif key == KEY_PO⁺
        POWINDOW = min.(POWINDOW .+ 1, [h,w])
    elseif key == KEY_PO_RESET
        POWINDOW = POWINDOWDEFAULT
    elseif key == KEY_RESET
        RESET = true
    elseif key == KEY_TICK
        return true # paused
    else
        TIMEOUT += 1
        return false
    end
    TIMEOUT = 0
    return false
end


end # module
