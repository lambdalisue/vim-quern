let s:sep = (!has('win32') && !has('win64')) || &shellslash ? '/' : '\\'
let s:rep = expand('<sfile>:p:h:h:h')
let s:lib = join([s:rep, 'rplugin', 'python3'], s:sep)

function! lista#python#init() abort
  if exists('s:initialized')
    return s:initialized
  elseif has('nvim')
    " If this function is called in Neovim, it is likely a bug
    throw 'A python.vim is for Vim. Use rpplugin in Neovim.'
  elseif !has('python3')
    echoerr 'vim-lista requires a Vim with Python3 support (+python3)'
    let s:initialized = 0
    return s:initialized
  endif
  try
    python3 << EOC
import sys
import vim
sys.path.insert(0, vim.eval('s:lib'))
EOC
    let s:initialized = 1
    return s:initialized
  catch
    echoerr v:exception
    echoerr v:throwpoint
    let s:initialized = 0
    return s:initialized
  endtry
endfunction

function! lista#python#start() abort
  if !lista#python#init()
    echoerr 'vim-lista is disabled.'
    return
  endif
  python3 << EOC
def _temporary_scope():
    # -------------------------------------------------------------------------
    import vim
    # NOTE:
    # vim.options['encoding'] returns bytes so use vim.eval('&encoding')
    ENCODING = vim.eval('&encoding')
    class Decorator:
        def __init__(self, component):
            self.component = component
            self.__class__ = self.__class__.extend(component.__class__)
        def __getattr__(self, name):
            value = getattr(self.component, name)
            return self.__class__.decorate(value)
        @classmethod
        def extend(cls, component_cls):
          decorator = type('DecoratorExtended', (cls,), {})
          def bind(attr):
            if hasattr(decorator, attr) or not hasattr(component_cls, attr):
              return
            ori = getattr(component_cls, attr)
            mod = lambda s, *a, **k: ori(s.component, *a, **k)
            setattr(decorator, attr, mod)
          for attr in component_cls.__dict__.keys():
            bind(attr)
          return decorator
        @classmethod
        def decorate(cls, component):
            if component in (vim.buffers, vim.windows, vim.tabpages, vim.current):
                return Decorator(component)
            elif isinstance(component, (vim.Buffer, vim.Window, vim.TabPage)):
                return Decorator(component)
            elif isinstance(component, (vim.List, vim.Dictionary, vim.Options)):
                return ContainerDecorator(component)
            return component
    class ContainerDecorator(Decorator):
        def __getitem__(self, key):
            value = self.component[key]
            if isinstance(value, bytes):
                value = value.decode(ENCODING)
            return value
        def __setitem__(self, key, value):
            if isinstance(value, str):
                value = value.encode(ENCODING)
            self.component[key] = value
    class Nvim(Decorator):
        def call(self, name, *args):
            result = self.Function(name)(*args)
            if isinstance(result, bytes):
                if result.startswith(b"\x80"):
                    result = "\udc80" + result[1:].decode(ENCODING)
                else:
                    result = result.decode(ENCODING)
            return result
    # -------------------------------------------------------------------------
    from lista.lista import Lista
    Lista(Nvim(vim)).start()
_temporary_scope()
del _temporary_scope
EOC
endfunction
