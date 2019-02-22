module CodeEnvironments

using SHA
using Base64
using Pkg

export
    CodeEnvironment,
    use_environment,
    environment_code

# A type which allows us to hide the details of Manifest.toml on a single
# source code line in jupyter, etc.
struct Base64Data
    data::String
end
Base.convert(::Type{String}, data::Base64Data) = String(base64decode(data.data))

"""
    CodeEnvironment(; project, manifest, name="")

"""
struct CodeEnvironment
    project::String
    manifest::String
    name::String
    fullname::String
    function CodeEnvironment(project::String, manifest::String, name::String)
        fullname = "CodeEnvironment_"              *
                   (isempty(name) ? "" : name*"_") *
                   bytes2hex(sha1(project*manifest))
        new(project, manifest, name, fullname)
    end
end

function CodeEnvironment(; project, manifest, name="", extras...)
    if !isempty(extras)
        # `extras` is present for forward compatibility: We may later want
        # extra info in the environment, but we don't yet know what it may be.
        @warn "CodeEnvironment() constructor: ignoring extra key value pairs" extras
    end
    project_str = convert(String, project)
    manifest_str = convert(String, manifest)
    CodeEnvironment(project_str, manifest_str, name)
end

function Base.show(io::IO, env::CodeEnvironment)
    manifest_nlines = sum(isequal('a'), env.manifest)
    print(io, env.fullname, "\n",
          "With project declaration and explicit dependencies (Project.toml):\n", env.project,
          "(+ detailed manifest of ", manifest_nlines, " lines)\n")
end

function _get_paths(env)
    envpath = joinpath(Pkg.envdir(), env.fullname)
    project_path = joinpath(envpath, "Project.toml")
    manifest_path = joinpath(envpath, "Manifest.toml")
    (envpath, project_path, manifest_path)
end

function check_environment(env)
    envpath, project_path, manifest_path = _get_paths(env)
    if !isdir(envpath)
        @info "Environment $(env.fullname) is not instantiated"
        return
    end

    project_ok  = env.project == read(project_path, String)
    manifest_ok = env.manifest == read(manifest_path, String)

    if !project_ok || !manifest_ok
        @error """
               Your code environment is inconsistent - it appears you have
               $(!project_ok ?
                 "added or removed packages from it manually." :
                 "updated the package versions in it manually.")

               We have loaded your installed version of this environment anyway
               but it is no longer a faithful copy of the reference environment!

               To fix this you have two options:
               * You may *update* the environment used by this script by
                 pasting the output of `environment_code()` over the top of the
                 code which calls `use_environment()`.
               * You may *revert* the local changes to your installed packages
                 with `use_environment(code_env, overwrite=true)`.
               """ reference_environment=env
    end
end

"""
    use_environment(env; overwrite=false)

Activate the environment `env`, instantiating it if necessary (installing,
building and precompiling all packages), or checking the existing environment
with the given name for consistency.
"""
function use_environment(env::CodeEnvironment; overwrite=false)
    envpath, project_path, manifest_path = _get_paths(env)
    newenv = !isdir(envpath)
    if overwrite || newenv
        if newenv
            mkpath(envpath)
            @info "Instantiating CodeEnvironment at $envpath"
        end
        write(project_path, env.project)
        write(manifest_path, env.manifest)
        Pkg.activate(envpath)
        Pkg.instantiate()
        Pkg.API.precompile()
    else
        @info "Activating existing environment at $envpath"
        check_environment(env)
        Pkg.activate(envpath)
    end
    nothing
end

"""
    environment_code([env::CodeEnvironment])

Generate julia code which may be pasted into a script or jupyter notebook in
order to set the environment.

If `env` is omitted, clone the current environment. Be careful doing this with
the default environment - you may end up with a lot of packages which your
current project doesn't need!

## Examples:

To get the current environment and put it in the system clipboard for pasting:

    clipboard(environment_code())

For use in jupyter, you may to print it to the screen instead if you are
running your jupyter kernel remotely:

    println(environment_code())
"""
function environment_code(env::CodeEnvironment)
    # To hide the environment guff in vim, use `set foldmethod=marker`
    namestr = isempty(env.name) ? "" : "name=$(repr(env.name)),"
    @info "Generating code for environment" env
    """
    using CodeEnvironments # {{{ Code environment setup
    code_env = CodeEnvironment($(namestr)project=CodeEnvironments.Base64Data($(repr(base64encode(env.project)))),manifest=CodeEnvironments.Base64Data($(repr(base64encode(env.manifest))))) # }}}
    use_environment(code_env)
    """
end

function environment_code()
    project_path = Pkg.Types.find_project_file() # FIXME: Call a public Pkg function for this?
    @info "Seeding CodeEnvironment with current project file" project_path
    environment_code(load_environment(project_path))
end

function load_environment(project_path)
    manifest_path = joinpath(dirname(Pkg.Types.find_project_file()), "Manifest.toml")
    CodeEnvironment(project=read(project_path, String), manifest=read(manifest_path, String))
end

end # module
