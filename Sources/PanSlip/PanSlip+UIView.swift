import UIKit

private var slipDirectionContext: UInt8 = 0
private var slipCompletionContext: UInt8 = 0

private var panSlipViewProxyContext: UInt8 = 0

extension PanSlip where Base: UIView {
    
    // MARK: - Properties
    
    private(set) var slipDirection: PanSlipDirection? {
        get {
            return objc_getAssociatedObject(base, &slipDirectionContext, defaultValue: nil)
        }
        set {
            objc_setAssociatedObject(base, &slipDirectionContext, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    private(set) var slipCompletion: (() -> Void)? {
        get {
            return objc_getAssociatedObject(base, &slipCompletionContext, defaultValue: nil)
        }
        set {
            objc_setAssociatedObject(base, &slipCompletionContext, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private var viewProxy: PanSlipViewProxy? {
        get {
            return objc_getAssociatedObject(base, &panSlipViewProxyContext, defaultValue: nil)
        }
        set {
            objc_setAssociatedObject(base, &panSlipViewProxyContext, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    // MARK: - Public methods
    
    public func enable(slipDirection: PanSlipDirection, slipCompletion: (() -> Void)?) {
        self.slipDirection = slipDirection
        self.slipCompletion = slipCompletion
        
        if viewProxy == nil {
            viewProxy = PanSlipViewProxy(view: base,
                                         slipDirection: slipDirection,
                                         slipCompletion: slipCompletion)
            viewProxy?.configure()
        }
    }
    
    public func disable() {
        slipDirection = nil
        slipCompletion = nil
        viewProxy = nil
    }
    
}

// MARK: - PanSlipViewProxy

private class PanSlipViewProxy: NSObject {
    
    // MARK: - Properties
    
    private unowned let view: UIView
    private var slipDirection: PanSlipDirection?
    private var slipCompletion: (() -> Void)?
    
    private lazy var panGesture: UIPanGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(panGesture(_:)))
    
    // MARK: - Con(De)structor
    
    init(view: UIView, slipDirection: PanSlipDirection, slipCompletion: (() -> Void)?) {
        self.view = view
        super.init()
        
        self.slipDirection = slipDirection
        self.slipCompletion = slipCompletion
    }
    
    // MARK: - Internal methods
    
    func configure() {
        view.addGestureRecognizer(panGesture)
    }
    
    // MARK: - Private methods
    
    private func unconfigure() {
        view.removeGestureRecognizer(panGesture)
    }
    
    private func slip(animated: Bool, duration: TimeInterval = 0.3, completion: (() -> Void)? = nil) {
        func slipUsingDirection() {
            guard let slipDirection = slipDirection else {return}
            
            defer {
                view.layoutIfNeeded()
            }
            
            let size = view.bounds
            switch slipDirection {
            case .leftToRight:
                view.transform = CGAffineTransform(translationX: size.width, y: 0)
            case .righTotLeft:
                view.transform = CGAffineTransform(translationX: -size.width, y: 0)
            case .topToBottom:
                view.transform = CGAffineTransform(translationX: 0, y: size.height)
            case .bottomToTop:
                view.transform = CGAffineTransform(translationX: 0, y: -size.height)
            }
        }
        
        guard animated else {
            view.removeFromSuperview()
            slipCompletion?()
            completion?()
            return
        }
        
        UIView.animate(withDuration: duration, animations: {
            slipUsingDirection()
        }) { (isFinished) in
            guard isFinished else {return}
            
            self.unconfigure()
            self.view.removeFromSuperview()
            self.slipCompletion?()
            
            completion?()
        }
    }
    
    private func rollback(duration: TimeInterval = 0.3, completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: duration, animations: {
            self.view.transform = CGAffineTransform.identity
            self.view.layoutIfNeeded()
        })
    }
    
    // MARK: - Private selector
    
    @objc private func panGesture(_ sender: UIPanGestureRecognizer) {
        guard let slipDirection = slipDirection else {return}
        
        let translation = sender.translation(in: view)
        let size = view.bounds.size
        var movementPercent: CGFloat?
        switch slipDirection {
        case .leftToRight:
            movementPercent = translation.x / size.width
        case .righTotLeft:
            movementPercent = -(translation.x / size.width)
        case .topToBottom:
            movementPercent = translation.y / size.height
        case .bottomToTop:
            movementPercent = -(translation.y / size.height)
        }
        
        guard let movement = movementPercent else {return}
        let downwardMovementPercent = fminf(fmaxf(Float(movement), 0.0), 1.0)
        let progress = CGFloat(fminf(downwardMovementPercent, 1.0))
        switch sender.state {
        case .changed:
            guard progress > 0 else {return}
            switch slipDirection {
            case .leftToRight, .righTotLeft:
                view.transform = CGAffineTransform(translationX: translation.x, y: view.frame.origin.y)
            case .topToBottom, .bottomToTop:
                view.transform = CGAffineTransform(translationX: view.frame.origin.x, y: translation.y)
            }
        case .cancelled:
            rollback()
        case .ended:
            let percentThreshold: CGFloat = (view as? PanSlipBehavior)?.percentThreshold ?? 0.3
            guard progress > percentThreshold else {
                rollback()
                return
            }
            
            slip(animated: true)
        default:
            break
        }
    }
}
