use v6;
use JSON::Fast;

class Pod::Coverage {
    my Bool $ignore-accessors = True;
    my Bool $anypod = False;
    #|Attribute list for skipping accessor methods
    has @!currentAttr;
    has @!results = ();

    method use-meta($metafile){
        my $mod = from-json slurp $metafile;
        for (flat @($mod<provides>//Empty)) -> $val {
            for $val.kv -> $k, $v {
                    Pod::Coverage.coverage($k,$k, $v);
            }
        }
    }

    #| Sometimes any block pod no matter what contains may be fine 
    method enable-anypod(Bool $value = True) {
        $anypod = $value;
    }

    method file-haspod($path, $packageStr) {
        unless read_pod($path).elems > 0 {
            my $cl = my class {};
            $cl.^set_name($packageStr);
            @!results.push: $cl;
        }
    }
    
    method coverage($toload, $packageStr, $path){
        my $i = Pod::Coverage.new;
        if $anypod {
            $i.file-haspod($path, $packageStr);
        }
        else {
            require ::($toload);
            #start from self        
            $i.parse(::($packageStr));
        }
        $i.correct-pod($path);
  
        $i.show-results($packageStr);

    }

    method show-results($packageStr) {
        if @!results {   
            for @!results.values -> $result {
                if $result.^can("package") {
                    say $result.package.^name ~ "::" ~ $result.name ~ " is not documented";
                }
                else {
                    say $result.^name ~ " is not documented";
                }
            }
        } else {
            say "$packageStr seems documented";
        }

    }
    
    #| goes through metaobject tree
    method parse($whoO) {
        if ($whoO.WHAT ~~ Routine) {
            # Because Routine is a class it must be checked before
            unless $whoO.WHY {
                if $whoO.WHAT ~~ Method {
                    
                    for @!currentAttr -> $attr {
                        if $attr.name.subst(/.\!/, "") ~~ $whoO.name {
                            
                            if $attr.has-accessor {
                                return if $ignore-accessors;
                                unless $attr.WHY {
                                    @!results.push: $attr;
                                }
                                return
                            }
                        }
                    }
                }
                @!results.push: $whoO;
            }  
        }    
        elsif ($whoO.HOW ~~ Metamodel::PackageHOW) {
            for $whoO.WHO.values -> $clazz {
                self.parse($clazz); 
            }
        }
        elsif ($whoO.HOW ~~ Metamodel::ModuleHOW) {
            for $whoO.WHO.values -> $clazz {
                if $clazz.^name eq 'EXPORT' {
                    for $clazz.WHO<ALL>.WHO.values -> $subr {
                        self.parse($subr);
                    }

                } else {
                    self.parse($clazz);
                }
                
            }
        } elsif ($whoO.HOW ~~ Metamodel::ClassHOW ) 
        {
            unless $whoO.WHY {
                @!results.push: $whoO;
            }
            
            @!currentAttr = $whoO.^attributes;
            
            for $whoO.^methods(:local) -> $m {                
                self.parse($m);
            }
            
            @!currentAttr = ();
            
            for $whoO.WHO<EXPORT>.WHO<ALL>.WHO.values -> $subr {   
                self.parse($subr);
            }
            
        }
        elsif ($whoO.HOW ~~ Metamodel::ParametricRoleGroupHOW) {
            for $whoO.^candidates -> $role {                
                self.parse($role);
            }
        }
        #        elsif ($whoO ~~ Grepper)
        #        {
        #todo

        #        }
        else {
            warn "What is " ~ $whoO.^name ~ " ?";
        }
    }

    method correct-pod($filename) {
        my @keywords = read_pod($filename);
        my @new_results;
        for @!results -> $result {
            # HACK
            my $name = $result.can("package") ?? $result.name !! $result.^name;
            if $result.WHAT ~~ Sub {  
                @new_results.push: $result unless @keywords.first(/[sub|routine|subroutine]\s+$name/);                
            } elsif $result.WHAT ~~ Routine {
                @new_results.push: $result unless @keywords.first(/[method]\s+$name/); 
            } else {
                @new_results.push: $result unless @keywords.first(/\s*$name/); 
            }
        }
        @!results =  @new_results;
        
    }

    sub read_pod($filename){
        return qqx/$*EXECUTABLE-NAME --doc=Keywords $filename/.lines;
            CATCH {
                warn "Could not open file $filename";
                return Empty;
        }    
    }
}

=begin pod

=head1 Pod::Coverage

=head1 SYNOPSIS

=begin code

git clone https://github.com/jonathanstowe/META6.git

cd META6

panda install ./

pod-coverage 

=end code 

or

=begin code

git clone https://github.com/jonathanstowe/META6.git

cd META6

pod-coverage --anypod

=end code 

=head2 method C<coverage>

=begin code
    
    Pod::Coverage.coverage("Mortgage","Mortgage");

=end code 

=head2 method C<use-meta>

=begin code

    Pod::Coverage.use-meta("/home/kamil/pod6-coverage/META.info");

=end code


=end pod
